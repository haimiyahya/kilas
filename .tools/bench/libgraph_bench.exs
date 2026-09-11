# libgraph projection + BlastRadius BFS benchmark (kilas spec §3/§4.3 algorithm)
Mix.install([{:libgraph, "~> 0.16"}])

defmodule Bench do
  @max_depth 5

  @labels %{"CALLS" => :calls, "TESTED_BY" => :tested_by, "DEPENDS_ON" => :depends_on,
            "IMPORTS" => :imports, "HAS_VULN" => :has_vuln, "MODIFIED_IN" => :modified_in}

  def load(path) do
    File.stream!(path)
    |> Stream.drop(1)
    |> Stream.map(fn line ->
      case String.split(String.trim_trailing(line), ",") do
        [label, src, dst, _count] -> {Map.fetch!(@labels, label), src, dst}
        [""] -> nil
      end
    end)
    |> Stream.reject(&is_nil/1)
    |> Enum.to_list()
  end

  # Spec §3 projection pseudocode (per-edge reduce)
  def project_reduce(rows) do
    Enum.reduce(rows, Graph.new(), fn {l, s, d}, g ->
      g |> Graph.add_vertex(s) |> Graph.add_vertex(d) |> Graph.add_edge(s, d, label: l)
    end)
  end

  # Bulk alternative
  def project_bulk(rows) do
    edges = Enum.map(rows, fn {l, s, d} -> Graph.Edge.new(s, d, label: l) end)
    Graph.add_edges(Graph.new(), edges)
  end

  # Spec §4.3 BlastRadius
  def blast_radius(g, node_id) do
    touched = callers_incl_self(g, MapSet.new([node_id]), MapSet.new([node_id]), 0)
    touched
    |> Enum.flat_map(fn v ->
      g |> Graph.out_edges(v) |> Enum.filter(&(&1.label == :tested_by)) |> Enum.map(& &1.v2)
    end)
    |> Enum.uniq()
  end

  defp callers_incl_self(_g, _frontier, seen, d) when d >= @max_depth, do: seen

  defp callers_incl_self(g, frontier, seen, d) do
    next =
      frontier
      |> Enum.flat_map(&Graph.in_neighbors(g, &1))
      |> MapSet.new()
      |> MapSet.difference(seen)

    case MapSet.size(next) do
      0 -> seen
      _ -> callers_incl_self(g, next, MapSet.union(seen, next), d + 1)
    end
  end

  def bench_bfs(g, n_nodes, runs) do
    times =
      for _ <- 1..runs do
        node = "n#{:rand.uniform(n_nodes) - 1}"
        {t, _} = :timer.tc(fn -> blast_radius(g, node) end)
        t
      end

    sorted = Enum.sort(times)
    %{
      p50: Enum.at(sorted, div(runs, 2)),
      p95: Enum.at(sorted, floor(runs * 0.95)),
      max: Enum.max(sorted),
      mean: div(Enum.sum(sorted), runs)
    }
  end

  def stat(name, us), do: :io_lib.format("~s: ~.2f ms", [name, us / 1000])
end

log = "/root/projects/kilas/.tools/bench/progress.log"
scales = %{"100" => 32, "1k" => 160, "5k" => 800, "10k" => 1600, "20k" => 3200,
           "30k" => 4800, "40k" => 6400, "50k" => 8000, "100k" => 16000,
           "150k" => 24000, "200k" => 30000, "500k" => 70000}
name = hd(System.argv())
n_nodes = Map.fetch!(scales, name)
path = "/root/projects/kilas/.tools/bench/data/#{name}_edges.csv"

File.rm(log)
step = fn msg -> File.write!(log, "[#{div(System.monotonic_time(:millisecond), 100) / 10}s] #{msg}\n", [:append]) end

step.("#{name}: start, mix deps ready")
{t_load, rows} = :timer.tc(fn -> Bench.load(path) end)
step.("#{name}: loaded #{length(rows)} rows in #{t_load / 1_000_000}s")

{t_reduce, g1} = :timer.tc(fn -> Bench.project_reduce(rows) end)
step.("#{name}: reduce projection done in #{t_reduce / 1_000_000}s")

{t_bulk, _g2} = :timer.tc(fn -> Bench.project_bulk(rows) end)
step.("#{name}: bulk projection done in #{t_bulk / 1_000_000}s")

bytes = :erts_debug.size(g1) * :erlang.system_info(:wordsize)
step.("#{name}: memory measured: #{div(bytes, 1024 * 1024)} MB")

{t_hub, _} = :timer.tc(fn -> Bench.blast_radius(g1, "n0") end)
step.("#{name}: hub warmup (n0) done in #{t_hub / 1_000_000}s")

bfs = Bench.bench_bfs(g1, n_nodes, 300)
step.("#{name}: 300 BFS runs done")

IO.puts("""
== #{name} (#{length(rows)} edges, #{Graph.num_vertices(g1)} vertices) ==
  csv load        #{Bench.stat("", t_load)}
  project reduce  #{Bench.stat("", t_reduce)}
  project bulk    #{Bench.stat("", t_bulk)}
  graph memory    #{div(bytes, 1024 * 1024)} MB
  hub BFS (n0)    #{Bench.stat("", t_hub)}
  BFS p50/p95/max #{Bench.stat("p50", bfs.p50)} / #{Bench.stat("p95", bfs.p95)} / #{Bench.stat("max", bfs.max)} (mean #{Bench.stat("", bfs.mean)})
""")
