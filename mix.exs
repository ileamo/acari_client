defmodule AcariClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :acari_client,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :ssl],
      mod: {AcariClient.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:acari, git: "https://github.com/ileamo/acari.git"},
      {:tunctl, git: "https://github.com/msantos/tunctl.git"},
      {:jason, "~> 1.0"},
      {:distillery, "~> 2.0"}
    ]
  end
end
