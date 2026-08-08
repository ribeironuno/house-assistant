defmodule BrainWeb.Router do
  use BrainWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :webhook_auth do
    plug :verify_webhook_token
  end

  scope "/", BrainWeb do
    pipe_through [:api, :webhook_auth]

    post "/webhook/whatsapp", WebhookController, :create
  end

  defp verify_webhook_token(conn, _opts) do
    secret = Application.get_env(:brain, :webhook_secret)

    case secret do
      nil ->
        conn

      "" ->
        conn

      expected ->
        case conn.req_headers
             |> Enum.find_value(fn
               {"x-webhook-token", val} -> val
               {"authorization", "Bearer " <> val} -> val
               _ -> nil
             end) do
          ^expected ->
            conn

          _ ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(401, ~s({"error":"unauthorized"}))
            |> Plug.Conn.halt()
        end
    end
  end
end
