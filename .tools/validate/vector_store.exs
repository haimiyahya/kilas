# Plug-and-play embedding store: one behaviour, two interchangeable backends.
#   Kilas.VectorStore.DuckDB  — duckdbex NIF + DuckDB vss (HNSW ANN)
#   Kilas.VectorStore.SQLite  — exqlite NIF + sqlite-vec vec0 (brute force)
# BACKEND=duckdb|sqlite runs one; default runs both and cross-checks top-k.
#
# Proven mechanics folded in from exqlite_vec_bench.exs (LE float blobs,
# vec0 MATCH) and the duckdbex HNSW probe (list -> ?::FLOAT[384] binding,
# LOAD vss then persistence SET, HNSW live during inserts).

Mix.install([{:duckdbex, "~> 0.3.7"}, {:exqlite, ">= 0.0.0"}])

defmodule Kilas.VectorStore do
  @moduledoc "Embedding store behaviour: both backends answer these four calls."
  @callback init(path :: String.t(), dim :: pos_integer) :: {:ok, store :: term} | {:error, term}
  @callback upsert(store :: term, id :: integer, vec :: [float]) :: :ok | {:error, term}
  @callback knn(store :: term, vec :: [float], k :: pos_integer) :: {:ok, [{id :: integer, dist :: float}]}
  @callback count(store :: term) :: {:ok, non_neg_integer}
end

defmodule Kilas.VectorStore.DuckDB do
  @behaviour Kilas.VectorStore

  def init(path, dim) do
    config = struct(Duckdbex.Config, maximum_memory: 536_870_912, maximum_threads: 4)
    with {:ok, db} <- Duckdbex.open(path, config),
         {:ok, conn} <- Duckdbex.connection(db),
         {:ok, _} <- Duckdbex.query(conn, "LOAD vss"),
         {:ok, _} <- Duckdbex.query(conn, "SET hnsw_enable_experimental_persistence=true"),
         {:ok, _} <- Duckdbex.query(conn, "CREATE OR REPLACE TABLE emb(id INTEGER PRIMARY KEY, vec FLOAT[#{dim}])"),
         {:ok, _} <- Duckdbex.query(conn, "CREATE INDEX emb_hnsw ON emb USING HNSW (vec)"),
         {:ok, ins} <- Duckdbex.prepare_statement(conn, "INSERT INTO emb VALUES (?, ?::FLOAT[#{dim}]) ON CONFLICT DO UPDATE SET vec = excluded.vec"),
         {:ok, knn} <- Duckdbex.prepare_statement(conn, "SELECT id, array_distance(vec, ?::FLOAT[#{dim}]) AS d FROM emb ORDER BY d LIMIT ?") do
      {:ok, {conn, ins, knn}}
    end
  end

  def upsert({_, ins, _}, id, vec) do
    case Duckdbex.execute_statement(ins, [id, vec]) do
      {:ok, _} -> :ok
      e -> e
    end
  end
  def knn({_, _, knn}, vec, k) do
    with {:ok, res} <- exec(knn, [vec, k]) do
      {:ok, Enum.map(Duckdbex.fetch_all(res), fn [id, d] -> {id, d} end)}
    end
  end
  def count({conn, _, _}) do
    with {:ok, res} <- Duckdbex.query(conn, "SELECT count(*) FROM emb") do
      [[n]] = Duckdbex.fetch_all(res)
      {:ok, n}
    end
  end
  defp exec(stmt, params) do
    case Duckdbex.execute_statement(stmt, params) do
      {:ok, _} = ok -> ok
      e -> e
    end
  end
end

defmodule Kilas.VectorStore.SQLite do
  @behaviour Kilas.VectorStore

  def init(path, dim) do
    with {:ok, conn} <- Exqlite.Sqlite3.open(path),
         :ok <- Exqlite.Sqlite3.enable_load_extension(conn, true),
         {:ok, st} <- Exqlite.Sqlite3.prepare(conn, "SELECT load_extension('#{Path.absname(".tools/validate/data/vec0")}')"),
         {:row, _} <- Exqlite.Sqlite3.step(conn, st),
         :ok <- Exqlite.Sqlite3.enable_load_extension(conn, false),
         {:ok, st} <- Exqlite.Sqlite3.prepare(conn, "CREATE VIRTUAL TABLE emb USING vec0(id INTEGER PRIMARY KEY, vec FLOAT[#{dim}])"),
         :done <- Exqlite.Sqlite3.step(conn, st),
         {:ok, ins} <- Exqlite.Sqlite3.prepare(conn, "INSERT OR REPLACE INTO emb(id, vec) VALUES (?, vec_f32(?))"),
         {:ok, knn} <- Exqlite.Sqlite3.prepare(conn, "SELECT id, distance FROM emb WHERE vec MATCH vec_f32(?) AND k = ? ORDER BY distance") do
      {:ok, {conn, ins, knn}}
    end
  end

  def upsert({conn, ins, _}, id, vec) do
    # vec_f32 expects little-endian float32; bare ::float-32 is big-endian on BEAM
    blob = for f <- vec, into: <<>>, do: <<f::float-32-little>>
    with :ok <- Exqlite.Sqlite3.bind_integer(ins, 1, id),
         :ok <- Exqlite.Sqlite3.bind_blob(ins, 2, blob),
         :done <- Exqlite.Sqlite3.step(conn, ins),
         do: :ok
  end

  def knn({conn, _, knn}, vec, k) do
    blob = for f <- vec, into: <<>>, do: <<f::float-32-little>>
    with :ok <- Exqlite.Sqlite3.bind_blob(knn, 1, blob),
         :ok <- Exqlite.Sqlite3.bind_integer(knn, 2, k) do
      drain(conn, knn, [])
    end
  end

  def count({conn, _, _}) do
    with {:ok, st} <- Exqlite.Sqlite3.prepare(conn, "SELECT count(*) FROM emb"),
         {:row, [n]} <- Exqlite.Sqlite3.step(conn, st),
         :done <- Exqlite.Sqlite3.step(conn, st),
         do: {:ok, n}
  end

  defp drain(conn, stmt, acc) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      :done -> {:ok, Enum.reverse(acc)}
      {:row, [id, d]} -> drain(conn, stmt, [{id, d} | acc])
      e -> e
    end
  end
end

defmodule Bench do
  @dim 384
  @n 1000
  @queries 25

  def vec(i), do: for(j <- 0..(@dim - 1), do: :math.sin(i / 100 + j / @dim))
  def qvec(m), do: for(j <- 0..(@dim - 1), do: :math.sin(m * 0.37 + j / @dim))

  def run(mod) do
    name = mod |> Module.split() |> List.last() |> Macro.underscore()
    path = Path.absname(".tools/validate/data/psn_#{name}.db")
    File.rm(path)
    {:ok, store} = mod.init(path, @dim)

    t0 = System.monotonic_time(:microsecond)
    Enum.each(1..@n, fn i -> :ok = mod.upsert(store, i, vec(i)) end)
    ins_us = System.monotonic_time(:microsecond) - t0

    if mod == Kilas.VectorStore.DuckDB, do: {:ok, _} = Duckdbex.query(elem(store, 0), "CHECKPOINT")

    results =
      for m <- 1..@queries do
        q = qvec(m)
        t = System.monotonic_time(:microsecond)
        {:ok, top} = mod.knn(store, q, 5)
        {System.monotonic_time(:microsecond) - t, Enum.map(top, &elem(&1, 0))}
      end

    lat = results |> Enum.map(&elem(&1, 0)) |> Enum.sort()
    tops = Enum.map(results, &elem(&1, 1))

    # ground truth: exact L2 brute force in Elixir
    truth =
      for m <- 1..@queries do
        q = qvec(m)
        1..@n
        |> Enum.map(fn i -> {i, Enum.zip_with([q, vec(i)], fn [a, b] -> (a - b) * (a - b) end) |> Enum.sum()} end)
        |> Enum.sort_by(&elem(&1, 1))
        |> Enum.take(5)
        |> Enum.map(&elem(&1, 0))
      end

    recalls = Enum.zip(truth, tops) |> Enum.map(fn {t, top} -> MapSet.new(t) |> MapSet.intersection(MapSet.new(top)) |> MapSet.size() end)
    {:ok, n} = mod.count(store)

    IO.puts(
      "#{String.pad_trailing(name <> " (" <> mod_name(mod) <> ")", 28)}" <>
        "upsert #{Float.round(ins_us / @n, 1)}us/row  KNN p50=#{Enum.at(lat, 12) / 1000}ms p90=#{Enum.at(lat, 22) / 1000}ms" <>
        "  recall(5)={min #{Enum.min(recalls)}, avg #{Float.round(Enum.sum(recalls) / @queries, 2)}}  count=#{n}"
    )

    {name, tops, truth}
  end

  defp mod_name(Kilas.VectorStore.DuckDB), do: "vss HNSW"
  defp mod_name(Kilas.VectorStore.SQLite), do: "vec0 brute"
end

backend =
  case System.get_env("BACKEND") do
    "duckdb" -> [Kilas.VectorStore.DuckDB]
    "sqlite" -> [Kilas.VectorStore.SQLite]
    _ -> [Kilas.VectorStore.DuckDB, Kilas.VectorStore.SQLite]
  end

n_queries = 25
results = Enum.map(backend, &Bench.run/1)

if length(results) == 2 do
  [{_, tops1, _}, {_, tops2, _}] = results
  agree = Enum.zip(tops1, tops2) |> Enum.count(fn {a, b} -> MapSet.new(a) == MapSet.new(b) end)
  IO.puts("backends agree on top-5 for #{agree}/#{n_queries} queries (both vs exact ground truth: see recall per backend)")
end
