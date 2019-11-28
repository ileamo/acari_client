defmodule AcariClient.API do
  def get_version() do
    {:ok, vsn} = :application.get_key(:acari_client, :vsn)
    %{result: vsn |> to_string()}
  end

  def restart() do
    Task.start(fn ->
      Process.sleep(1000)
      :init.restart()
    end)

    %{result: "Client will be restarted"}
  end

  def halt() do
    Task.start(fn ->
      Process.sleep(1000)
      :erlang.halt()
    end)

    %{result: "Client will be halted"}
  end
end
