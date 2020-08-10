defmodule AcariClient.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      AcariClient.Endpoint,
      Acari.Sup,
      AcariClient.SetRuleAgent,
      #{Task.Supervisor, name: AcariClient.TaskSup},
      #AcariClient.LoopTest
      AcariClient.Master
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_all, name: AcariClient.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
