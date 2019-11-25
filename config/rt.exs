import Config
config_path = "/etc/acari/system_config.exs"

if File.exists?(config_path) do
  for {application, kv} <- Config.Reader.read!(config_path),
      {key, value} <- kv do
    config application, key, value
  end
end
