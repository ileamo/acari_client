defmodule AcariClient.LoopTest do
  use GenServer
  require Logger
  require Acari.Const, as: Const

  @test_tuns_num 25
  @links ["BEELINE", "MEGAFON", "MTS", "TELE2"]

  defmodule State do
    defstruct [
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
    :ets.new(:cl_tuns, [:set, :protected, :named_table])

    master_pid = self()

    # Task.start(fn ->
    for i <- 0..@test_tuns_num |> Enum.drop(1) do
      :ok = Acari.start_tun(cl_name(i), master_pid)
    end

    # end)

    # TEST CYCLE
    Task.Supervisor.start_child(AcariClient.TaskSup, __MODULE__, :test, [], restart: :permanent)

    {:noreply, %State{}}
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

  def handle_cast(mes, state) do
    Logger.warn("Client get unknown message: #{inspect(mes)}")
    {:noreply, state}
  end

  defp exec_client_method(state, _tun_name, "exec_sh", %{"script" => script}) do
    Acari.exec_sh(script)
    state
  end

  defp exec_client_method(state, tun_name, "get_exec_sh", %{"id" => id, "script" => script}) do
    get_exec_sh(
      script,
      &put_data_to_server/2,
      %{id: id, tun_name: tun_name}
    )

    state
  end

  defp exec_client_method(state, tun_name, method, params) do
    Logger.error("Bad message from #{tun_name}; method: #{method}, params: #{inspect(params)}")
    state
  end

  defp restart_tunnel(tun_name) do
    num = tun_name |> String.slice(-6, 6) |> String.to_integer()
    m1 = Enum.at(@links, rem(num, 4))
    m2 = Enum.at(@links, rem(num + 1, 4))
    start_sslink(tun_name, m1)
    start_sslink(tun_name, m2)
    send_csq(tun_name, m1)
    send_csq(tun_name, m2)
  end

  defp start_sslink(tun, link) do
    {:ok, request} =
      Jason.encode(%{
        id: "NSG1700_1812#{tun |> String.slice(-6, 6)}",
        link: link,
        params: %{ifname: get_ifname(tun)}
      })

    {:ok, _pid} =
      Acari.add_link(tun, link, fn
        :connect ->
          connect(
            %{
              host: Application.get_env(:acari_client, :host),
              port: Application.get_env(:acari_client, :port)
            },
            request
          )

        :restart ->
          true
      end)
  end

  defp get_ifname(tun) do
    [{_, ifname}] = :ets.lookup(:cl_tuns, tun)
    ifname
  end

  defp connect(%{host: host, port: port} = params, request) do
    case :ssl.connect(to_charlist(host), port, [packet: 2], 5000) do
      {:ok, sslsocket} ->
        :ssl.send(sslsocket, <<1::1, 0::15>> <> request)
        sslsocket

      {:error, reason} ->
        Logger.warn("Can't connect #{host}:#{port}: #{inspect(reason)}")
        Process.sleep(10_000)
        connect(params, request)
    end
  end

  defp cl_name(i) do
    "cl_#{:io_lib.format("~6..0B", [i])}"
  end

  @impl true
  def handle_call({:start_tun, num}, _from, state) do
    res = Acari.start_tun(cl_name(num), self())
    {:reply, res, state}
  end

  # API
  def start_tun(num) do
    GenServer.call(__MODULE__, {:start_tun, num})
  end

  # TEST
  def test() do
    Process.sleep(Enum.random(1..20) * 1000)
    tun_name = cl_name(Enum.random(1..@test_tuns_num))

    case Enum.random(0..9) do
      0 ->
        for link_name <- @links do
          Task.start_link(__MODULE__, :stop_start_link, [tun_name, link_name])
        end

      _ ->
        link_name = Enum.random(@links)
        Task.start_link(__MODULE__, :stop_start_link, [tun_name, link_name])
    end

    test()
  end

  def stop_start_tun() do
    tun_name = cl_name(Enum.random(1..@test_tuns_num))

    case Acari.stop_tun(tun_name) do
      :ok ->
        Process.sleep(Enum.random(10..120) * 1000)
        start_tun(tun_name)

      _ ->
        nil
    end
  end

  def stop_start_link(tun_name, link_name) do
    # TODO if no tun__name
    case Acari.del_link(tun_name, link_name) do
      :ok ->
        Process.sleep(Enum.random(20..120) * 1000)
        start_sslink(tun_name, link_name)

        Process.sleep(Enum.random(10..20) * 1000)
        send_csq(tun_name, link_name)

      _ ->
        nil
    end
  end

  defp send_csq(tun_name, link_name) do
    System.cmd("zabbix_sender", [
      "-zlocalhost",
      "-p50051",
      "-s",
      "NSG1700_1812#{tun_name |> String.slice(-6, 6)}",
      "-kcsq[#{link_name}]",
      "-o#{Enum.random(10..31)}"
    ])
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
end
