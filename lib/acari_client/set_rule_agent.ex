defmodule AcariClient.SetRuleAgent do
  use Agent

  def start_link(_) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def get_state() do
    Agent.get(__MODULE__, & &1)
  end

  def set(table, src) do
    Agent.update(__MODULE__, fn
      %{^table => ^src} = state ->
        state

      state ->
        delete_all_rules(table)

        case System.cmd("ip", ["rule", "add", "from", src, "table", "#{table}"],
               stderr_to_stdout: true
             ) do
          {_, 0} ->
            state |> Map.put(table, src)

          _ ->
            state
        end
    end)
  end

  defp delete_all_rules(table) do
    case System.cmd("ip", ["rule", "delete", "from", "0/0", "to", "0/0", "table", "#{table}"],
           stderr_to_stdout: true
         ) do
      {_, 0} -> delete_all_rules(table)
      _ -> :ok
    end
  end
end
