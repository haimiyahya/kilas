defmodule TsNif.MixProject do
  use Mix.Project

  def project do
    [
      app: :ts_nif,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: deps()
    ]
  end

  defp deps do
    [{:rustler, "~> 0.34"}]
  end
end
