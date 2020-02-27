defmodule AcariClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :acari_client,
      version: "1.0.3-x2",
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        acari_x86: [
          include_executables_for: [:unix],
          applications: [runtime_tools: :permanent],
          runtime_config_path: "config/rt.exs",
          steps: [:assemble, :tar],
          include_erts: true
        ],
        acari_arm: [
          include_executables_for: [:unix],
          applications: [runtime_tools: :permanent],
          #runtime_config_path: "config/rt.exs",
          include_erts: "/opt/erlang/arm_rt_eabi/erlang/erts-10.5.3"
        ],
        acari_powerpc: [
          include_executables_for: [:unix],
          applications: [runtime_tools: :permanent],
          #runtime_config_path: "config/rt.exs",
          include_erts: "/opt/erlang/powerpc_rt/erlang/erts-10.5.3"
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :ssl],
      mod: {AcariClient.Application, []}
    ]
  end

  defp elixirc_paths(_),
    do: [
      # "acari_lib",
      "lib"
    ]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:acari, git: "https://github.com/ileamo/acari.git"},
      # {:procket, git: "https://github.com/ileamo/procket.git", override: true},
      {:tunctl, git: "https://github.com/ileamo/tunctl.git"},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"},
      {:temp, "~> 0.4"},
      {:loggix, "~> 0.0.9"}
    ]
  end
end
