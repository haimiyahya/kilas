defmodule TreeSitterNif do
  use Rustler, otp_app: :ts_nif, crate: :tree_sitter_nif

  def parse_go(_source), do: :erlang.nif_error(:not_loaded)
end
