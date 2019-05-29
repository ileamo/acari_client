defmodule AcariClient do
  def get_host_env(:test) do
    {:ok,
     %{
       "ethaddr" => "00:09:56:32:00:CF",
       "fw_media" => "nfs",
       "hw_sign" => "001",
       "nsg_device" => "NSG1700",
       "serial_num" => "1701000070"
     }}
  end

  def get_host_env() do
    # TODO now only for NSG devices
    with {:ok, text} <- File.read("/proc/nsg/env"),
         env_map = %{"nsg_device" => dev, "serial_num" => sn} <-
           ~r|([^=]+)=([^\n]+)\n|
           |> Regex.scan(text <> "\n")
           |> Enum.map(fn [_, k, v] -> {k, v} end)
           |> Enum.into(%{}) do
      {:ok, env_map |> Map.put("id", "#{dev}_#{sn}")}
    else
      {:error, res} -> {:error, res}
      res -> {:error, res}
    end
  end
end
