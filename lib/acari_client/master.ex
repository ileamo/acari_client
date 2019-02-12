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
    :ets.insert(:cl_tuns, {tun_name, ifname})

    restart_tunnel(tun_name)
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
    IO.inspect(json)

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

  defp exec_client_method(state, _tun_name, "sfx", %{"script" => num}, attach) do
    with sfx when is_binary(sfx) <- attach |> Enum.at(num),
         {:ok, file_path} <- Temp.open("acari", &IO.binwrite(&1, sfx)),
         :ok <- File.chmod(file_path, 0o755),
         {_, 0} <- System.cmd(file_path, ["--quiet", "--nox11"], stderr_to_stdout: true) do
      File.rm(file_path)
    end

    state
  end

  defp exec_client_method(state, tun_name, method, params, _attach) do
    Logger.error("Bad message from #{tun_name}; method: #{method}, params: #{inspect(params)}")
    state
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
    [{_, ifname}] = :ets.lookup(:cl_tuns, tun_name)
    ifname
  end

  defp connect(%{dev: dev, host: host, port: port} = params, request) do
    with {:ok, ip} <- get_if_addr(dev),
         {:ok, sslsocket} <- :ssl.connect(to_charlist(host), port, [packet: 2, ip: ip], 5000) do
      :ssl.send(sslsocket, <<1::1, 0::15>> <> request)
      sslsocket
    else
      reason ->
        Logger.warn("Can't connect #{dev}::#{host}:#{port}: #{inspect(reason)}")
        Process.sleep(10_000)
        connect(params, request)
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
             method: "put_data",
             params: %{
               id: arg[:id],
               data: data
             }
           }) do
      Acari.TunMan.send_tun_com(arg[:tun_name], Const.master_mes(), json)
    else
      res -> Logger.error("put_data: Can't parse JSON: #{inspect(res)}")
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

  defp get_if_addr(if_name) do
    with {:ok, list} <- :inet.getifaddrs(),
         {_, addr_list} <- list |> Enum.find(fn {name, _} -> name == to_charlist(if_name) end),
         {:ok, addr} <- addr_list |> Keyword.fetch(:addr) do
      {:ok, addr}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :noiface}
    end
  end
end
