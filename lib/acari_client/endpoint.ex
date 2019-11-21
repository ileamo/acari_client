defmodule AcariClient.Endpoint do
  @moduledoc """

  API examples:

      curl -H "Content-Type: application/json" \
      -X POST \
      -d '{"fn":"get_version"}' \
      http://localhost:50021/api

      wget -qO- \
      --header "Content-Type: application/json" \
      --post-data '{"fn":"get_version"}' \
      http://localhost:50021/api
  """
  require Logger
  use Plug.Router

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(_opts) do
    with {:ok, config} <-
           Application.fetch_env(:acari_client, __MODULE__) do
      Logger.info("Starting server: #{inspect(config)}")
      Code.ensure_loaded?(AcariClient.API)
      Plug.Cowboy.http(__MODULE__, [], config)
    end
  end

  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  post "/api" do
    Logger.info("API request: #{inspect(conn.body_params)}")

    res = api(conn)
    {:ok, json} = Jason.encode(res)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, json)
  end

  match _ do
    send_resp(conn, 404, "Requested page not found!")
  end

  defp api(conn) do
    case conn.body_params do
      %{"fn" => func} ->
        params =
          case conn.body_params["params"] || [] do
            p when is_list(p) -> p
            p -> [p]
          end

        with func when is_atom(func) <-
               (try do
                  String.to_existing_atom(func)
                rescue
                  _ -> 0
                end),
             true <- function_exported?(AcariClient.API, func, length(params)) do
          apply(AcariClient.API, func, [])
        else
          _ -> %{error: "No such function: #{func}/#{length(params)}"}
        end
        |> Map.merge(%{fn: func, params: params})

      %{} ->
        %{error: "No fn key"}

      _ ->
        %{error: "Bad JSON request"}
    end
  end
end
