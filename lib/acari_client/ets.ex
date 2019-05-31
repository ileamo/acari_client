defmodule AcariClient.Ets do
  def init() do
    :ets.new(:links, [:set, :public, :named_table])
  end

  def update_link(tun_name, link_server, up, opts \\ nil) do
    [link_name, server] = link_server |> String.split("@", parts: 2)
    key = {tun_name, link_name, server}
    :ets.insert(:links, {key, tun_name, link_name, server, up, opts})
  end

  def get_number_of_up_links(dev) do
    :ets.match(:links, {:_, :_, dev, :_, true, :_})
    |> length()
  end

  def set_last_restart_tm(dev, tm) do
    :ets.insert(:links, {dev, tm})
  end

  def get_last_restart_tm(dev) do
    case :ets.match(:links, {dev, :"$1"}) do
      [[tm]] -> tm
      _ -> 0
    end
  end
end
