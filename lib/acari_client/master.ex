defmodule AcariClient.Master do
  use GenServer
  require Logger
  require Acari.Const, as: Const

  defmodule State do
    defstruct [
      :env,
      :tun_name,
      :ifname
    ]
  end

  def start_link(params) do
    GenServer.start_link(__MODULE__, params, name: __MODULE__)
  end

  ## Callbacks
  @impl true
  def init(params) do
    {:ok, params, {:continue, :init}}
  end

  @impl true
  def handle_continue(:init, _params) do
    with {:ok, env = %{"id" => id}} <- AcariClient.get_host_env() do
      :ets.new(:cl_tuns, [:set, :protected, :named_table])
      master_pid = self()
      :ok = Acari.start_tun(id, master_pid)
      {:noreply, %State{env: env}}
    else
      res ->
        Logger.error("Can't get host environment: #{inspect(res)}")
        {:noreply, %State{}}
    end
  end

  @impl true
  def handle_cast({:tun_started, %{tun_name: tun_name, ifname: ifname}}, state) do
    Logger.debug("Acari client receive :tun_started from #{tun_name}:#{ifname}")
    :ets.insert(:cl_tuns, {tun_name, ifname, false})
    restart_tunnel(tun_name)
    Task.start_link(__MODULE__, :get_conf, [tun_name])
    {:noreply, state}
  end

  def handle_cast({:peer_started, tun_name}, state) do
    Logger.debug("Acari client receive :peer_started from #{tun_name}")
    {:noreply, state}
  end

  def handle_cast({:sslink_opened, _tun_name, _sslink_name, _num}, state) do
    {:noreply, state}
  end

  def handle_cast({:sslink_closed, _tun_name, _sslink_name, _num}, state) do
    {:noreply, state}
  end

  def handle_cast({:master_mes, tun_name, json}, state) do
    with {:ok, %{"method" => method, "params" => params}} <- Jason.decode(json) do
      exec_client_method(state, tun_name, method, params)
    else
      res ->
        Logger.error("Bad master_mes from #{tun_name}: #{inspect(res)}")
    end

    {:noreply, state}
  end

  def handle_cast({:master_mes_plus, tun_name, json, attach}, state) do
    with {:ok, %{"method" => method, "params" => params}} <- Jason.decode(json) do
      exec_client_method(state, tun_name, method, params, attach)
    else
      res ->
        Logger.error("Bad master_mes_plus from #{tun_name}: #{inspect(res)}")
    end

    {:noreply, state}
  end

  def handle_cast(:stop_master, state) do
    {:stop, :shutdown, state}
  end

  def handle_cast(mes, state) do
    Logger.warn("Client get unknown message: #{inspect(mes)}")
    {:noreply, state}
  end

  def get_conf(tun_name, delay \\ 1000) do
    Process.sleep(delay)
    if conf_get?(tun_name) do
      :ok
    else
      request = %{
        method: "get.conf",
        params: %{
          id: "NSG1700_1812#{tun_name |> String.slice(-6, 6)}"
        }
      }
      Acari.send_master_mes(tun_name, request)
      get_conf(tun_name, delay * 2)
    end
  end

  defp exec_client_method(state, tun_name, method, params, attach \\ [])

  defp exec_client_method(state, _tun_name, "exec_sh", %{"script" => script}, _attach) do
    Acari.exec_sh(script)
    state
  end

  defp exec_client_method(
         state,
         tun_name,
         "get_exec_sh",
         %{"id" => id, "script" => script},
         _attach
       ) do
    get_exec_sh(
      script,
      &put_data_to_server/2,
      %{id: id, tun_name: tun_name}
    )

    state
  end

  defp exec_client_method(state, tun_name, "put.conf", %{"script" => num}, attach) do
    Logger.info("#{tun_name}: Get configuration")
    :ets.update_element(:cl_tuns, tun_name, {3, true})
    exec_sfx(attach |> Enum.at(num))

    state
  end

  defp exec_client_method(state, tun_name, method, params, _attach) do
    Logger.error("Bad message from #{tun_name}; method: #{method}, params: #{inspect(params)}")
    state
  end

  defp exec_sfx(sfx) do
    with sfx when is_binary(sfx) <- sfx,
         {:ok, file_path} <- Temp.open("acari", &IO.binwrite(&1, sfx)),
         :ok <- File.chmod(file_path, 0o755),
         {_, 0} <- System.cmd(file_path, ["--quiet", "--nox11"], stderr_to_stdout: true) do
      File.rm(file_path)
    else
      res -> Logger.error("SFX error: #{inspect(res)}")
    end
  end

  defp restart_tunnel(tun_name) do
    with links when is_list(links) <- Application.get_env(:acari_client, :links),
         :ok <- links |> Enum.each(fn link -> start_sslink(tun_name, link) end) do
      :ok
    else
      res -> Logger.error("Bad links config: #{inspect(res)}")
    end
  end

  defp start_sslink(tun_name, link) do
    with link_name when is_binary(link_name) <- link |> Keyword.get(:dev),
         dev when is_binary(dev) <- link |> Keyword.get(:dev),
         table when is_number(table) <- link |> Keyword.get(:table),
         [server | _] when is_list(server) <- link |> Keyword.get(:servers) do
      {:ok, request} =
        Jason.encode(%{
          id: tun_name,
          link: link_name,
          params: %{ifname: get_ifname(tun_name)}
        })

      {:ok, _pid} =
        Acari.add_link(tun_name, link_name, fn
          :connect ->
            connect(
              %{
                dev: dev,
                table: table,
                host: server |> Keyword.get(:host),
                port: server |> Keyword.get(:port)
              },
              request
            )

          :restart ->
            true
        end)
    end
  end

  defp get_ifname(tun_name) do
    [{_, ifname, _}] = :ets.lookup(:cl_tuns, tun_name)
    ifname
  end

  defp conf_get?(tun) do
    [{_, _, conf}] = :ets.lookup(:cl_tuns, tun)
    conf
  end

  defp connect(%{dev: dev, table: table, host: host, port: port} = params, request) do
    with {:ok, src} <- get_if_addr(dev),
         :ok <- set_routing(dev, host, src |> :inet.ntoa() |> to_string(), table),
         {:ok, sslsocket} <- :ssl.connect(to_charlist(host), port, [packet: 2, ip: src], 5000) do
      Logger.info("#{dev}: Connect #{host}:#{port}")
      :ssl.send(sslsocket, <<1::1, 0::15>> <> request)
      sslsocket
    else
      reason ->
        Logger.warn("#{dev}: Can't connect #{host}:#{port}: #{inspect(reason)}")
        Process.sleep(10_000)
        connect(params, request)
    end
  end

  defp set_routing(dev, host, src, table) do
    System.cmd("ip", ["route", "delete", host <> "/32", "table", "#{table}"])
    delete_all_rules(table)
    System.cmd("ip", ["rule", "add", "from", src, "table", "#{table}"])
    System.cmd("ip", ["route", "add", host <> "/32", "dev", dev, "table", "#{table}"])
    :ok
  end

  defp delete_all_rules(table) do
    case System.cmd("ip", ["rule", "delete", "from", "0/0", "to", "0/0", "table", "#{table}"]) do
      {_, 0} -> delete_all_rules(table)
      _ -> :ok
    end
  end

  @impl true
  def handle_call({:start_tun, tun_name}, _from, state) do
    res = Acari.start_tun(tun_name, self())
    {:reply, res, state}
  end

  # API
  def start_tun(tun_name) do
    GenServer.call(__MODULE__, {:start_tun, tun_name})
  end

  def stop_master() do
    IO.inspect(:code.purge(__MODULE__), label: "PURGE")
    IO.inspect(:code.atomic_load([__MODULE__]), label: "LOAD")
    Process.sleep(2 * 1000)
    GenServer.cast(__MODULE__, :stop_master)
  end

  defp put_data_to_server(arg, data) do
    with {:ok, json} <-
           Jason.encode(%{
             method: "put.data",
             params: %{
               id: arg[:id],
               data: data
             }
           }) do
      Acari.TunMan.send_tun_com(arg[:tun_name], Const.master_mes(), json)
    else
      res -> Logger.error("put.data: Can't parse JSON: #{inspect(res)}")
    end
  end

  defp get_exec_sh(script, func, arg) do
    Task.start(fn ->
      case System.cmd("sh", ["-c", script |> String.replace("\r\n", "\n")], stderr_to_stdout: true) do
        {data, 0} -> func.(arg, data)
        {err, code} -> func.(arg, "Script `#{script}` exits with code #{code}, output: #{err}")
      end
    end)
  end

  def get_if_addr(if_name) do
    with {:ok, list} <- :inet.getifaddrs(),
         if_name_cl <- to_charlist(if_name),
         {^if_name_cl, addr_list} <-
           list |> Enum.find({:error, :noiface}, fn {name, _} -> name == if_name_cl end),
         {:ok, {_, _, _, _} = addr} <- addr_list |> Keyword.fetch(:addr),
         {:ok, flags} <- addr_list |> Keyword.fetch(:flags),
         {true, true} <-
           flags
           |> Enum.reduce({false, false}, fn
             :up, {_, r} -> {true, r}
             :running, {u, _} -> {u, true}
             _, acc -> acc
           end) do
      {:ok, addr}
    else
      {:error, reason} -> {:error, reason}
      :error -> {:error, :noaddr}
      {true, false} -> {:error, :norunning}
      {false, _} -> {:error, :ifdown}
      res -> {:error, inspect(res)}
    end
  end
end
