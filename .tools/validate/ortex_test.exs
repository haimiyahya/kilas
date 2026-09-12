# T2#12 Ortex + bge-micro-v2 INT8 ONNX (384-dim, CLS pooling).
# Target: 8-12ms/embed (paper-03 §3). Measures tokenize + infer latency, RSS, cosine sanity.
Mix.install([{:ortex, ">= 0.0.0"}, {:tokenizers, ">= 0.0.0"}, {:nx, ">= 0.0.0"}])

models_dir = "/root/projects/kilas/.tools/validate/models"
{:ok, tok} = Tokenizers.Tokenizer.from_file(models_dir <> "/tokenizer.json")
tok = tok |> Tokenizers.Tokenizer.disable_padding() |> Tokenizers.Tokenizer.set_truncation(max_length: 512)
model = Ortex.load(models_dir <> "/model_quantized.onnx")

embed = fn tok, text ->
  {:ok, enc} = Tokenizers.Tokenizer.encode(tok, text)
  n_tok = length(Tokenizers.Encoding.get_ids(enc))
  ids = Tokenizers.Encoding.get_ids(enc)
  mask = Tokenizers.Encoding.get_attention_mask(enc)
  types = Tokenizers.Encoding.get_type_ids(enc)

  inputs = {
    Nx.tensor([ids], type: :s64),
    Nx.tensor([mask], type: :s64),
    Nx.tensor([types], type: :s64)
  }

  {lhs} = Ortex.run(model, inputs)
  [cls | _] = Nx.to_flat_list(lhs) |> Enum.chunk_every(384)
  norm = :math.sqrt(Enum.reduce(cls, 0.0, fn x, acc -> acc + x * x end))
  vec = Enum.map(cls, &(&1 / norm))
  {n_tok, vec}
end

cos = fn a, b ->
  Enum.zip(a, b) |> Enum.reduce(0.0, fn {x, y}, s -> s + x * y end)
end

code1 = "def commit(tree), do: :ets.insert(:commits, {:erlang.phash2(tree), tree})"
code2 = "def lookup(sha), do: :ets.lookup(:commits, sha) |> hd()"
code3 = "The quick brown fox jumps over the lazy dog near the river bank at sunset."

{t, {n1, v1}} = :timer.tc(fn -> embed.(tok, code1) end)
IO.puts("first embed (cold): #{t / 1000}ms, tokens=#{n1}, dims=#{length(v1)}")

for _ <- 1..3, do: embed.(tok, code1)

sim_12 = cos.(v1, elem(embed.(tok, code2), 1))
sim_13 = cos.(v1, elem(embed.(tok, code3), 1))
IO.puts("cosine: code-vs-code=#{Float.round(sim_12, 3)} code-vs-fox=#{Float.round(sim_13, 3)} (expect first > second)")

chunks =
  Enum.map(0..99, fn i -> code1 <> " # v#{rem(i, 17)} def f#{i}(x), do: x + #{rem(i, 7)}" end)

prep = fn c ->
  {:ok, enc} = Tokenizers.Tokenizer.encode(tok, c)
  [
    Tokenizers.Encoding.get_ids(enc),
    Tokenizers.Encoding.get_attention_mask(enc),
    Tokenizers.Encoding.get_type_ids(enc)
  ]
end

infer = fn m3 ->
  {lhs} = Ortex.run(model, {
    Nx.tensor([Enum.at(m3, 0)], type: :s64),
    Nx.tensor([Enum.at(m3, 1)], type: :s64),
    Nx.tensor([Enum.at(m3, 2)], type: :s64)
  })

  [cls | _] = Nx.to_flat_list(lhs) |> Enum.chunk_every(384)
  cls
end

{t_all, {tok_us_list, run_us_list}} =
  :timer.tc(fn ->
    for c <- chunks do
      {t1, m3} = :timer.tc(fn -> prep.(c) end)
      {t2, _cls} = :timer.tc(fn -> infer.(m3) end)
      {t1, t2}
    end
    |> Enum.unzip()
  end)

med = fn xs ->
  s = Enum.sort(xs)
  %{p50: Enum.at(s, 49), p90: Enum.at(s, 89), max: Enum.at(s, -1)}
end

fmt = fn xs ->
  m = med.(xs)
  "p50=#{m.p50 / 1000}ms p90=#{m.p90 / 1000}ms max=#{m.max / 1000}ms"
end

IO.puts("tokenize (100 chunks): #{fmt.(tok_us_list)}")
IO.puts("infer (100 chunks): #{fmt.(run_us_list)}")
IO.puts("total wall: #{t_all / 1000}ms")

rss_txt = File.read!("/proc/self/status")
rss_txt |> String.split("\n") |> Enum.find(&String.contains?(&1, "VmRSS")) |> IO.puts()

tok_lens = Enum.map(chunks, fn c -> {:ok, e} = Tokenizers.Tokenizer.encode(tok, c); length(Tokenizers.Encoding.get_ids(e)) end)
IO.puts("chunk tokens: min=#{Enum.min(tok_lens)} max=#{Enum.max(tok_lens)} avg=#{div(Enum.sum(tok_lens), 100)}")
