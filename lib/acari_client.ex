defmodule AcariClient do
  if Mix.env() == :prod do
    def get_host_env() do
      # TODO now only for NSG devices
      with {:ok, text} <- File.read("/proc/nsg/env"),
           {:ok, regex} <- Regex.compile("([^=]+)=([^\n]+)\n"),
           env_map = %{"nsg_device" => dev, "serial_num" => sn} <-
             regex
             |> Regex.scan(text <> "\n")
             |> Enum.map(fn [_, k, v] -> {k, v} end)
             |> Enum.into(%{}) do
        {:ok, env_map |> Map.put("id", "#{dev}_#{sn}")}
      else
        {:error, res} -> {:error, res}
        res -> {:error, res}
      end
    end
  else
    def get_host_env() do
      {:ok,
       %{
         "ethaddr" => "00:09:56:32:00:CF",
         "fw_media" => "nfs",
         "hw_sign" => "001",
         "nsg_device" => "NSG1810",
         "serial_num" => "1410001259",
         "id" => "NSG1810_1410001259"
       }}
    end
  end
end
