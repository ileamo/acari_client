defmodule AcariClient.LoopTest do
  use GenServer
  require Logger
  require Acari.Const, as: Const

  @test_tuns_num 25

  @links [
    # %{name: "m1", host: "acari-foo", port: 50019},
    # %{name: "m2", host: "acari-foo", port: 50019},
    # %{name: "m1", host: "acari-bar", port: 50019},
    # %{name: "m2", host: "acari-bar", port: 50019},
    # %{name: "m1", host: "acari-baz", port: 50019},
    # %{name: "m2", host: "acari-baz", port: 50019}
    # %{name: "m1", host: "10.0.10.3", port: 50019},
    # %{name: "m2", host: "10.0.10.3", port: 50019},
    # %{name: "m1", host: "localhost", port: 52019},
    # %{name: "m2", host: "localhost", port: 52019},
    %{name: "m1", host: "localhost", port: 50019, proto: :ssl},
    %{name: "m2", host: "localhost", port: 50020, proto: :gen_tcp}
  ]

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

    Task.Supervisor.start_child(AcariClient.TaskSup, __MODULE__, :sensor, [], restart: :permanent)

    {:noreply, %State{}}
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
          # ,
          id: tun_name
          # client_ifname: get_ifname(tun_name)
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

  defp restart_tunnel(tun_name) do
    for link <- @links do
      start_sslink(tun_name, link.name, link.host, link.port, link.proto)
      send_csq(tun_name, link.name)
    end
  end

  defp start_sslink(tun, link, host, port, proto) do
    {:ok, request} =
      Jason.encode(%{
        id: tun,
        link: link,
        params: %{ifname: get_ifname(tun)}
      })

    {:ok, _pid} =
      Acari.add_link(tun, "#{link}@#{host}:#{port}", fn
        :connect ->
          connect(
            %{
              proto: proto,
              host: host,
              port: port
            },
            request
          )

        :restart ->
          true

      end)
  end

  defp get_ifname(tun) do
    [{_, ifname, _}] = :ets.lookup(:cl_tuns, tun)
    ifname
  end

  defp conf_get?(tun) do
    [{_, _, conf}] = :ets.lookup(:cl_tuns, tun)
    conf
  end

  defp connect(%{proto: proto, host: host, port: port} = params, request) do
    connect_opts =
      [packet: 2] ++
        case proto do
          :ssl -> [versions: [:"tlsv1.3", :"tlsv1.2"]]
          _ -> []
        end

    case proto.connect(to_charlist(host), port, connect_opts, 5000) do
      {:ok, sslsocket} ->
        proto.send(sslsocket, <<1::1, 0::15>> <> request)
        sslsocket

      {:error, reason} ->
        Logger.warn("Can't connect #{host}:#{port}: #{inspect(reason)}")
        Process.sleep(10_000)
        connect(params, request)
    end
  end

  defp cl_name(i) do
    "NSG1700_1812#{:io_lib.format("~6..0B", [i])}"
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

    case Enum.random(0..3) do
      0 ->
        case Enum.random(0..3) do
          0 ->
            for link <- @links do
              Process.sleep(Enum.random(1..2) * 1000)

              Task.start(__MODULE__, :stop_start_link, [
                tun_name,
                link.name,
                link.host,
                link.port,
                link.proto
              ])
            end

          _ ->
            nm = Enum.random(["m1", "m2"])

            for link <-
                  @links
                  |> Enum.filter(fn %{name: name} ->
                    name == nm
                  end) do
              Process.sleep(Enum.random(1..2) * 1000)

              Task.start(__MODULE__, :stop_start_link, [
                tun_name,
                link.name,
                link.host,
                link.port,
                link.proto
              ])
            end
        end

      _ ->
        link = Enum.random(@links)

        Task.start(__MODULE__, :stop_start_link, [
          tun_name,
          link.name,
          link.host,
          link.port,
          link.proto
        ])
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

  def stop_start_link(tun_name, link_name, host, port, proto) do
    # TODO if no tun__name
    case Acari.del_link(tun_name, "#{link_name}@#{host}:#{port}") do
      :ok ->
        Process.sleep(Enum.random(20..120) * 1000)
        start_sslink(tun_name, link_name, host, port, proto)

        Process.sleep(Enum.random(10..20) * 1000)
        send_csq(tun_name, link_name)

      _ ->
        nil
    end
  end

  def sensor() do
    Process.sleep(60_000)

    for i <- 0..@test_tuns_num |> Enum.drop(1) do
      tun_name = cl_name(i)
      send_csq(tun_name, Enum.at(@links, 0).name)
      send_csq(tun_name, Enum.at(@links, 1).name)
    end

    sensor()
  end

  defp send_csq(tun_name, link_name) do
    with ifname <- get_ifname(tun_name),
         {:ok, dstaddr} <- get_if_dstaddr(ifname),
         zserv <- dstaddr |> Tuple.to_list() |> Enum.join("."),
         csq <- Enum.random(10..31) do
      System.cmd("zabbix_sender", [
        "-z",
        zserv,
        "-p50051",
        "-s",
        tun_name,
        "-kcsq[#{link_name}]",
        "-o#{csq}"
      ])
    else
      _ -> nil
    end
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

  defp get_if_dstaddr(if_name) do
    with {:ok, list} <- :inet.getifaddrs(),
         if_name_cl <- to_charlist(if_name),
         {^if_name_cl, addr_list} <-
           list |> Enum.find({:error, :noiface}, fn {name, _} -> name == if_name_cl end),
         {:ok, {_, _, _, _} = addr} <- addr_list |> Keyword.fetch(:dstaddr),
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
