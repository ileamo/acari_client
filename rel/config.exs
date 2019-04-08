# Import all plugins from `rel/plugins`
# They can then be used by adding `plugin MyPlugin` to
# either an environment, or release definition, where
# `MyPlugin` is the name of the plugin module.
~w(rel plugins *.exs)
|> Path.join()
|> Path.wildcard()
|> Enum.map(&Code.eval_file(&1))

use Mix.Releases.Config,
  # This sets the default release built by `mix release`
  default_release: :default,
  # This sets the default environment used by `mix release`
  default_environment: Mix.env()

# For a full list of config options for both releases
# and environments, visit https://hexdocs.pm/distillery/config/distillery.html

# You may define one or more environments in this file,
# an environment's settings will override those of a release
# when building in that environment, this combination of release
# and environment configuration is called a profile

environment :dev do
  # If you are running Phoenix, you should make sure that
  # server: true is set and the code reloader is disabled,
  # even in dev mode.
  # It is recommended that you build with MIX_ENV=prod and pass
  # the --env flag to Distillery explicitly if you want to use
  # dev mode.
  set(dev_mode: true)
  set(include_erts: false)
  set(cookie: :"`3nj5f2N9;Lj>vtB`QE]c|w(t/aEWLE]r>P.b47^v_!k2Xk.I8{b%AH*OVQ5B{lK")
end

environment :prod do
  set(include_erts: "/home/igor/nsg/LoRa/erlang")
  # set(include_erts: false)
  set(include_src: false)
  set(cookie: :"c92rvv<Ywq;{}e.q]R_n|HJheAnb0riySGEFG}gsqo&*dJLMKc?N7qfHVee/8=dX")
  set(vm_args: "rel/vm.args")
end

environment :docker do
  set(dev_mode: false)
  set(include_erts: true)
  set(include_src: false)

  
  set(vm_args: "rel/vm.args")
  set(
    cookie:
      :crypto.hash(:sha256, :crypto.strong_rand_bytes(25)) |> Base.encode16() |> String.to_atom()
  )

  set(
    overlays: [
      {:copy, "rel/runtime_config.exs", "etc/runtime_config.exs"}
    ]
  )
end

# You may define one or more releases in this file.
# If you have not set a default release, or selected one
# when running `mix release`, the first release in the file
# will be used by default

release :acari_client do
  set(version: current_version(:acari_client))

  set(
    config_providers: [
      {Mix.Releases.Config.Providers.Elixir, ["${RELEASE_ROOT_DIR}/etc/runtime_config.exs"]}
    ]
  )

  set(
    overlays: [
      {:copy, "rel/runtime_config.exs", "etc/runtime_config_example.exs"},
      {:copy, "rel/acari_config.exs", "etc/acari_config_example.exs"}
    ]
  )

  set(
    applications: [
      :runtime_tools,
      acari_client: :permanent
    ]
  )
end
