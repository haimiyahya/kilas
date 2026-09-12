# T1#7 ETS + MemGit commit-path micro-bench (spec v2: ETS read <0.01ms, MemGit commit <0.5ms)
# No deps — plain elixir. Models spec §"ETS Tables — In-Memory Only" exactly:
# blobs (sha256 content-addressed), trees (filepath -> blob_hash), commits (hash,tree,parent,msg).

tables = [:memgit_commits, :memgit_trees, :memgit_blobs]
Enum.each(tables, &:ets.new(&1, [:set, :public, :named_table]))

# --- 1. raw ETS lookup ---
:ets.insert(:memgit_blobs, {"seed", "x"})
:ets.lookup(:memgit_blobs, "seed") # warm
n_reads = 100_000
{t_us, _} = :timer.tc(fn ->
  for _ <- 1..n_reads, do: :ets.lookup(:memgit_blobs, "seed")
end)
IO.puts("ETS lookup x#{n_reads}: #{Float.round(t_us / n_reads, 3)}us/op (target <10us)")

# --- 2. MemGit commit path ---
# file content of ~2KB (typical function-sized chunk)
content = String.duplicate("defmodule Auth do\n  def hash_password(p), do: :crypto.hash(:sha256, p)\nend\n", 25)
filepath = "lib/auth.ex"
parent = String.duplicate("0", 64)

entries0 = %{"lib/other.ex" => String.duplicate("a", 64)}

commit = fn entries, i ->
  content = <<"defmodule Auth do\n  def f", :erlang.integer_to_binary(i)::binary, "() do :ok end\nend\n", String.duplicate("x", 2000)::binary>>
  blob_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  :ets.insert(:memgit_blobs, {blob_hash, content})
  entries = Map.put(entries, filepath, blob_hash)
  tree_bin = entries |> Enum.sort() |> :erlang.term_to_binary()
  tree_hash = :crypto.hash(:sha256, tree_bin) |> Base.encode16(case: :lower)
  :ets.insert(:memgit_trees, {tree_hash, entries})
  ts = System.system_time(:millisecond)
  msg = "edit #{i}"
  commit_hash = :crypto.hash(:sha256, <<tree_hash::binary, parent::binary, msg::binary>>) |> Base.encode16(case: :lower)
  :ets.insert(:memgit_commits, {commit_hash, tree_hash, parent, msg, :agent1, ts})
  {commit_hash, entries}
end

{_, entries} = commit.(entries0, 0) # warm JIT + tables
n_commits = 1000
times = for i <- 1..n_commits do
  {us, _} = :timer.tc(fn -> commit.(entries, i) end)
  us
end
times = Enum.sort(times)
p = fn q -> Enum.at(times, trunc(q * (n_commits - 1))) end
IO.puts("MemGit.commit x#{n_commits}: p50=#{p.(0.5)}us p90=#{p.(0.9)}us max=#{List.last(times)}us (target <500us)")

# size sanity
IO.puts("tables: commits=#{:ets.info(:memgit_commits, :size)} trees=#{:ets.info(:memgit_trees, :size)} blobs=#{:ets.info(:memgit_blobs, :size)}")
IO.puts("mem=#{div(:erlang.memory(:total), 1_048_576)}MB")
