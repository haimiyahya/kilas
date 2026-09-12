# T1#8 :fs_poll fallback watcher test (paper-03 §7) — detection latency + poll cost.
# FINDING: Elixir :file.read_file_info mtime is second-granularity here (raw stat is ns),
# so a poller MUST compare {mtime, size} (or hash); content of varying size makes edits visible.

defmodule PollBench do
  def wait_change(path, ref, t0) do
    Process.sleep(25)
    st = File.stat!(path)
    cur = {st.mtime, st.size}
    if cur != ref do
      System.monotonic_time(:millisecond) - t0
    else
      wait_change(path, ref, t0)
    end
  end
end

dir = ".tools/validate/data/fs_poll_tree"
File.rm_rf!(dir)
File.mkdir_p!(dir)
path = Path.join(dir, "watched.ex")
File.write!(path, "a = 1\n")

delays =
  for round <- 1..30 do
    toucher =
      spawn(fn ->
        Process.sleep(:rand.uniform(500))
        File.write!(path, String.duplicate("a", round) <> "\n")
      end)

    st = File.stat!(path)
    d = PollBench.wait_change(path, {st.mtime, st.size}, System.monotonic_time(:millisecond))
    Process.exit(toucher, :kill)
    d
  end

sorted = Enum.sort(delays)
IO.puts("detection latency, 30 rounds, ~500ms poll (25ms probe, {mtime,size} compare): min=#{hd(sorted)}ms p50=#{Enum.at(sorted, 15)}ms max=#{List.last(sorted)}ms")

scan = fn ->
  Path.wildcard(Path.join(dir, "*.go"))
  |> Enum.map(&File.stat!(&1))
end

for i <- 1..1000, do: File.write!(Path.join(dir, "f#{i}.go"), "package main\n")
scan.() # warm
n_scans = 50
t0 = System.monotonic_time(:microsecond)
for _ <- 1..n_scans, do: scan.()
per = div(System.monotonic_time(:microsecond) - t0, n_scans)
IO.puts("1000-file tree scan (wildcard+stat): #{per}us/poll -> at 500ms = #{Float.round(per / 500_000 * 100, 3)}% of one core")
File.rm_rf!(dir)
