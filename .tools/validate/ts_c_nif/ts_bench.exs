# T2#13 bench: tree-sitter Go parse latency through C NIF. Target <5ms (v2 §02).
defmodule TreeSitterCNif do
  @nif "/root/projects/kilas/.tools/validate/ts_c_nif/tree_sitter_cnif"
  def parse_go(src), do: :erlang.nif_error(:not_loaded)

  def init do
    case :erlang.load_nif(@nif, 0) do
      :ok -> :ok
      {:error, {:reload, _}} -> :ok
      e -> e
    end
  end
end

case TreeSitterCNif.init() do
  :ok -> :ok
  other -> raise "nif load failed: #{inspect(other)}"
end

fn_tpl = """
func f<%= i %>(x int, s string) (int, error) {
  if x > <%= i %> {
    return x * <%= i %>, nil
  }
  type point<%= i %> struct {
    X, Y int
    name string
  }
  p := &point<%= i %>{X: x, Y: <%= i %>, name: s}
  for j := 0; j < x; j++ {
    p.Y += j * <%= i %>
  }
  m := map[string][]int{"a": {1, <%= i %>}, "b": {<%= i %>, 2, 3}}
  delete(m, "a")
  var w io.Writer = os.Stdout
  fmt.Fprintf(w, "%v %s\\n", p, s)
  return p.Y, errors.New("eof")
}
"""

file = fn n_fns ->
  funcs = Enum.map(1..n_fns, &String.replace(fn_tpl, "<%= i %>", Integer.to_string(&1))) |> Enum.join("\n")
  """
  package kilas

  import (
    "errors"
    "fmt"
    "io"
    "os"
  )

  #{funcs}
  """
end

{ok, n, has_err} = TreeSitterCNif.parse_go(file.(20))
IO.puts("sanity parse: #{ok} nodes=#{n} has_error=#{has_err} (expect ok/false)")

Enum.each([{10, "small ~50 lines"}, {30, "medium ~150 lines"}, {100, "large ~500 lines"}], fn {nf, label} ->
  src = file.(nf)
  bytes = byte_size(src)
  TreeSitterCNif.parse_go(src) # warm
  lat =
    for _ <- 1..50 do
      t = System.monotonic_time(:microsecond)
      {:ok, _, _} = TreeSitterCNif.parse_go(src)
      System.monotonic_time(:microsecond) - t
    end

  s = Enum.sort(lat)
  IO.puts("#{label} (#{nf} funcs, #{bytes}B): p50=#{Enum.at(s, 25) / 1000}ms p90=#{Enum.at(s, 45) / 1000}ms max=#{List.last(s) / 1000}ms")
end)
