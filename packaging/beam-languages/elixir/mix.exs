defmodule SSHFling.MixProject do
  use Mix.Project

  def project do
    [
      app: :sshfling,
      version: "0.0.0",
      elixir: ">= 1.14.0 and < 2.0.0",
      start_permanent: Mix.env() == :prod,
      deps: [],
      package: package(),
      description: "Elixir launcher for the bundled SSHFling runtime"
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/GRWLX/sshfling"},
      files: ["lib", "priv/runtime", "mix.exs", "LICENSE", "README.md"]
    ]
  end
end
