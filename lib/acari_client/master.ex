defmodule AcariClient.Master do
  use GenServer
  require Logger
  require Acari.Const, as: Const

  alias AcariClient.Ets

  defmodule State do
    defstruct [
      :env,
      :conf
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
    with {:ok, env = %{"id" => id}} <- AcariClient.get_host_env(),
         {:ok, conf} <- get_conf() do
      Logger.info("Configuration:\n#{inspect(conf, pretty: true)}")
      :ets.new(:cl_tuns, [:set, :protected, :named_table])
      Ets.init()
      master_pid = self()
      :ok = Acari.start_tun(id, master_pid, iface_conf: conf[:iface])
      {:noreply, %State{env: env, conf: conf}}
    else
      res ->
        res =
          case res do
            {:error, reason} when is_binary(reason) -> reason
            res -> inspect(res)
          end

        Logger.error("Can't get configuration or host environment: #{res}")
        {:noreply, %State{}}
    end
  end

  defp get_conf() do
    try do
      {conf, _} = Code.eval_file("/etc/acari/acari_config.exs")
      {:ok, conf}
    rescue
      x ->
        {:error, inspect(x)}
    end
  end

  @impl true
  def handle_cast({:tun_started, %{tun_name: tun_name, ifname: ifname}}, state) do
    Logger.debug("Acari client receive :tun_started from #{tun_name}:#{ifname}")
    :ets.insert(:cl_tuns, {tun_name, ifname, false})
    ip_addr_add(ifname, state.conf)
    restart_tunnel(tun_name, state.conf)
    # Task.start_link(__MODULE__, :get_conf_from_server, [tun_name])
    {:noreply, state}
  end

  def handle_cast({:peer_started, tun_name}, state) do
    Logger.debug("Acari client receive :peer_started from #{tun_name}")
    {:noreply, state}
  end

  def handle_cast({:sslink_opened, tun_name, sslink_name, _num}, state) do
    Ets.update_link(tun_name, sslink_name, true)
    {:noreply, state}
  end

  def handle_cast({:sslink_closed, tun_name, sslink_name, _num}, state) do
    Ets.update_link(tun_name, sslink_name, false)
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

  def get_conf_from_server(tun_name, delay \\ 1000) do
    Process.sleep(delay)

    if conf_get?(tun_name) do
      :ok
    else
      request = %{
        method: "get.conf",
        params: %{
          id: tun_name,
          client_ifname: get_ifname(tun_name)
        }
      }

      Acari.send_master_mes(tun_name, request)
      get_conf_from_server(tun_name, delay * 2)
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
         %{"id" => id, "script" => num} = _params,
         attach
       ) do
    get_exec_sh(
      attach |> Enum.at(num),
      &put_data_to_server/2,
      %{id: id, tun_name: tun_name}
    )

    state
  end

  defp exec_client_method(state, tun_name, "put.conf", %{"script" => num}, attach) do
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
         {res, 0} <- System.cmd(file_path, ["--quiet", "--nox11"], stderr_to_stdout: true) do
      Logger.info("Set config output:\n#{res}")
      File.rm(file_path)
    else
      res -> Logger.error("SFX error: #{inspect(res)}")
    end
  end

  defp get_exec_sh(script, func, arg) do
    Task.start(fn ->
      with script when is_binary(script) <- script,
           {:ok, file_path} <- Temp.open("acari", &IO.binwrite(&1, script)),
           :ok <- File.chmod(file_path, 0o755),
           data <-
             :os.cmd((file_path <> " --quiet --nox11") |> String.to_charlist(), %{
               max_size: 1024 * 128
             }) do
        File.rm(file_path)
        func.(arg, data)
      else
        {:error, reason} -> func.(arg, "Can't open temporary file: #{reason}")
      end
    end)
  end

  defp restart_tunnel(tun_name, conf) do
    with links when is_list(links) <- conf |> Keyword.get(:links),
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
         server_list when is_list(server_list) <- link |> Keyword.get(:servers) do
      for server when is_list(server) <- server_list do
        {:ok, request} =
          Jason.encode(%{
            id: tun_name,
            link: link_name,
            params: %{ifname: get_ifname(tun_name)}
          })

        host = server |> Keyword.get(:host)
        port = server |> Keyword.get(:port)

        {:ok, _pid} =
          Acari.add_link(tun_name, "#{link_name}@#{host}:#{port}", fn
            :connect ->
              connect(
                %{
                  tun_name: tun_name,
                  dev: dev,
                  table: table,
                  host: host,
                  port: port,
                  restart_script: link |> Keyword.get(:restart_script)
                },
                request
              )

            :restart ->
              true
          end)
      end
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

  defp connect(%{dev: dev, table: table, host: host, port: port} = params, request, attempt \\ 0) do
    with {:ok, src} <- get_if_addr(dev),
         :ok <- set_routing(dev, host, src |> :inet.ntoa() |> to_string(), table),
         {:ok, sslsocket} <-
           (
             Logger.info("#{dev}: Try connect #{host}:#{port}")
             :ssl.connect(to_charlist(host), port, [packet: 2, ip: src], 20_000)
           ) do
      Logger.info("#{dev}: Connect #{host}:#{port}")
      :ssl.send(sslsocket, <<1::1, 0::15>> <> request)
      sslsocket
    else
      reason ->
        Logger.warn("#{dev}: Can't connect #{host}:#{port}: #{inspect(reason)}")

        attempt =
          cond do
            attempt >= 3 and is_binary(params[:restart_script]) and
              Ets.get_number_of_up_links(dev) == 0 and
                :erlang.system_time(:second) - Ets.get_last_restart_tm(dev) > 120 ->
              Acari.exec_sh(params[:restart_script])
              Logger.warn("#{dev}: Restart device")
              Ets.set_last_restart_tm(dev, :erlang.system_time(:second))
              Process.sleep(30_000)
              0

            true ->
              attempt
          end

        Process.sleep(10_000)
        connect(params, request, attempt + 1)
    end
  end

  def ip_addr_add(ifname, conf) do
    with iface_conf when is_list(iface_conf) <- conf[:iface],
         addr when is_binary(addr) <- iface_conf[:addr] do
      params =
        iface_conf
        |> Keyword.take([:peer, :broadcast])
        |> Enum.map(fn {k, v} -> [to_string(k), v] end)
        |> List.flatten()

      System.cmd("ip", ["addr", "flush", "dev", ifname], stderr_to_stdout: true)
      System.cmd("ip", ["addr", "add", "dev", ifname, addr] ++ params, stderr_to_stdout: true)
    else
      _ -> Logger.warn("No iface address in configuration")
    end
  end

  defp set_routing(dev, host, src, table) do
    AcariClient.SetRuleAgent.set(table, src)

    System.cmd("ip", ["route", "add", host <> "/32", "dev", dev, "table", "#{table}"],
      stderr_to_stdout: true
    )

    :ok
  end

  @impl true
  def handle_call({:start_tun, tun_name}, _from, state) do
    res = Acari.start_tun(tun_name, self(), iface_conf: state.conf[:iface])
    {:reply, res, state}
  end

  # API
  def start_tun(tun_name) do
    GenServer.call(__MODULE__, {:start_tun, tun_name})
  end

  def stop_master() do
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
