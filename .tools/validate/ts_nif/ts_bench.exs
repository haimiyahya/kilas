# T2#13 bench v2: same parse measurements, now through the real Rustler NIF.
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

{ok, n, has_err} = TreeSitterNif.parse_go(file.(20))
IO.puts("sanity parse: #{ok} nodes=#{n} has_error=#{has_err} (expect ok/false)")

Enum.each([{10, "small ~50 lines"}, {30, "medium ~150 lines"}, {100, "large ~500 lines"}], fn {nf, label} ->
  src = file.(nf)
  bytes = byte_size(src)
  TreeSitterNif.parse_go(src)
  lat =
    for _ <- 1..50 do
      t = System.monotonic_time(:microsecond)
      {:ok, _, _} = TreeSitterNif.parse_go(src)
      System.monotonic_time(:microsecond) - t
    end

  s = Enum.sort(lat)
  IO.puts("#{label} (#{nf} funcs, #{bytes}B): p50=#{Enum.at(s, 25) / 1000}ms p90=#{Enum.at(s, 45) / 1000}ms max=#{List.last(s) / 1000}ms")
end)
