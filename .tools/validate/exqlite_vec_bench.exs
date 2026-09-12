# T2#9 exqlite driver: load vec0 extension + KNN through the NIF (repeat of T0#6 at 10k).
Mix.install([{:exqlite, ">= 0.0.0"}])

alias Exqlite.Sqlite3

defmodule Bench do
  def drain(conn, stmt) do
    case Sqlite3.step(conn, stmt) do
      :done -> :ok
      {:row, _} -> drain(conn, stmt)
      other -> throw(other)
    end
  end
end

db_path = Path.absname(".tools/validate/data/exqlite_vec.db")
File.rm(db_path)

{:ok, conn} = Sqlite3.open(db_path)
:ok = Sqlite3.enable_load_extension(conn, true)
vec_path = Path.absname(".tools/validate/data/vec0")
{:ok, st} = Sqlite3.prepare(conn, "SELECT load_extension('#{vec_path}')")
{:row, _} = Sqlite3.step(conn, st)
:ok = Sqlite3.enable_load_extension(conn, false)
{:ok, st} = Sqlite3.prepare(conn, "SELECT vec_version()")
{:row, [ver]} = Sqlite3.step(conn, st)
:done = Sqlite3.step(conn, st)
IO.puts("vec0 loaded through exqlite: #{ver}")

{:ok, st} = Sqlite3.prepare(conn, "CREATE VIRTUAL TABLE v USING vec0(id INTEGER PRIMARY KEY, emb FLOAT[384])")
:done = Sqlite3.step(conn, st)

t0 = System.monotonic_time(:millisecond)
{:ok, ins} = Sqlite3.prepare(conn, "INSERT INTO v(id, emb) VALUES (?, vec_f32(?))")
{:ok, st} = Sqlite3.prepare(conn, "BEGIN")
:done = Sqlite3.step(conn, st)

Enum.each(1..10_000, fn i ->
  # vec_f32 expects little-endian float32; bare ::float-32 is big-endian on BEAM
  blob = :binary.copy(<<:math.sin(i / 100)::float-32-little>>, 384)
  :ok = Sqlite3.bind_integer(ins, 1, i)
  :ok = Sqlite3.bind_blob(ins, 2, blob)
  :done = Sqlite3.step(conn, ins)
end)

{:ok, st} = Sqlite3.prepare(conn, "COMMIT")
:done = Sqlite3.step(conn, st)

ins_ms = System.monotonic_time(:millisecond) - t0
IO.puts("insert 10k via exqlite: #{ins_ms}ms total, #{Float.round(ins_ms / 10_000 * 1000, 1)}us/row")

{:ok, knn} = Sqlite3.prepare(conn, "SELECT id, distance FROM v WHERE emb MATCH vec_f32(?) ORDER BY distance LIMIT 5")

lat =
  for q <- 1..50 do
    blob = :binary.copy(<<(0.001 * q + 0.1)::float-32-little>>, 384)
    t = System.monotonic_time(:microsecond)
    :ok = Sqlite3.bind_blob(knn, 1, blob)
    {:row, _} = Sqlite3.step(conn, knn)
    Bench.drain(conn, knn)
    System.monotonic_time(:microsecond) - t
  end

lat = Enum.sort(lat)
IO.puts("KNN k=5 n=10k via exqlite: p50=#{Enum.at(lat, 25) / 1000}ms p90=#{Enum.at(lat, 45) / 1000}ms max=#{List.last(lat) / 1000}ms (target <10ms)")
Sqlite3.close(conn)
