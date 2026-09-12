Mix.install([{:ortex, ">= 0.0.0"}, {:tokenizers, ">= 0.0.0"}, {:nx, ">= 0.0.0"}])
models_dir = "/root/projects/kilas/.tools/validate/models"
{:ok, tok} = Tokenizers.Tokenizer.from_file(models_dir <> "/tokenizer.json")
tok = tok |> Tokenizers.Tokenizer.disable_padding() |> Tokenizers.Tokenizer.set_truncation(max_length: 512)
model = Ortex.load(models_dir <> "/model_quantized.onnx")
base = "defmodule Chunk do\n  def handle(msg, state), do: {:reply, msg, %{state | count: state.count + 1}}\nend\n"
for target <- [128, 256, 512] do
  text = String.duplicate(base, Kernel.div(target, 20) + 1)
  {:ok, enc} = Tokenizers.Tokenizer.encode(tok, text)
  n = length(Tokenizers.Encoding.get_ids(enc))
  i = Nx.tensor([Tokenizers.Encoding.get_ids(enc)], type: :s64)
  m = Nx.tensor([Tokenizers.Encoding.get_attention_mask(enc)], type: :s64)
  t = Nx.tensor([Tokenizers.Encoding.get_type_ids(enc)], type: :s64)
  for _ <- 1..2, do: Ortex.run(model, {i, m, t})
  lat = for _ <- 1..15 do
    {us, _} = :timer.tc(fn -> {lhs} = Ortex.run(model, {i, m, t}); Nx.to_flat_list(lhs) |> hd() end)
    us
  end
  s = Enum.sort(lat)
  IO.puts("n=#{n} tokens: p50=#{Enum.at(s, 7) / 1000}ms max=#{Enum.at(s, -1) / 1000}ms")
end
