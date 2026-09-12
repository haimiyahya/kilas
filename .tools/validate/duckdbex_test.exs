# T2#11 duckdbex NIF (spec dep v2 §03 ~0.3.7): precompiled NIF; repeat T0#2 upsert bench through the driver.
# File DB on f2fs, PRIMARY KEY + ON CONFLICT DO UPDATE, memory_limit 512MB threads=4 (paper-03 §7 config).
# CLI baseline (row 2): single upsert p50 6-8ms flat 1k->50k; batch100 9-15ms; bulk ~30us/row.
Mix.install([{:duckdbex, "~> 0.3.7"}])

config = struct(Duckdbex.Config, maximum_memory: 536_870_912, maximum_threads: 4)
{:ok, db} = Duckdbex.open(Path.absname(".tools/validate/data/duckdbex_bench.db"), config)
{:ok, conn} = Duckdbex.connection(db)
{:ok, _} = Duckdbex.query(conn, "CREATE OR REPLACE TABLE edges(src INTEGER, dst INTEGER, PRIMARY KEY(src, dst))")
{:ok, ins} = Duckdbex.prepare_statement(conn, "INSERT INTO edges VALUES (?, ?) ON CONFLICT DO UPDATE SET dst = ?")

single = fn n ->
  {:ok, _} = Duckdbex.query(conn, "DELETE FROM edges")
  for i <- 1..n, do: {:ok, _} = Duckdbex.execute_statement(ins, [i, i + 1, i + 1])
  lat =
    for i <- (n + 1)..(n + 60) do
      t = System.monotonic_time(:microsecond)
      {:ok, _} = Duckdbex.execute_statement(ins, [i, i + 1, i + 1])
      System.monotonic_time(:microsecond) - t
    end

  lat |> Enum.sort() |> then(fn s -> "n=#{n}: single upsert p50=#{Enum.at(s, 30) / 1000}ms p90=#{Enum.at(s, 54) / 1000}ms max=#{List.last(s) / 1000}ms" end)
end

Enum.each([1000, 10_000, 50_000], fn n ->
  {:ok, _} = Duckdbex.query(conn, "DELETE FROM edges")
  {:ok, _} = Duckdbex.query(conn, "INSERT INTO edges SELECT i AS src, i+1 AS dst FROM (SELECT unnest(generate_series(1, #{n})) AS i)")
  IO.puts(single.(n))
end)

Enum.each([10_000, 50_000], fn n ->
  {:ok, _} = Duckdbex.query(conn, "DELETE FROM edges")
  t = System.monotonic_time(:microsecond)
  {:ok, _} = Duckdbex.query(conn, "INSERT INTO edges SELECT i AS src, i+1 AS dst FROM (SELECT unnest(generate_series(1, #{n})) AS i)")
  us = System.monotonic_time(:microsecond) - t
  IO.puts("bulk #{n}: #{us / 1000}ms total, #{Float.round(us / n, 2)}us/row")
end)

{:ok, res} = Duckdbex.query(conn, "SELECT count(*) FROM edges")
IO.inspect(Duckdbex.fetch_all(res), label: "final count")
{:ok, res} = Duckdbex.query(conn, "SELECT library_version()")
IO.inspect(Duckdbex.fetch_all(res), label: "duckdb version")
