defmodule BrainWeb.Router do
  use BrainWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BrainWeb.Layouts, :app}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :put_csp_header
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :webhook_auth do
    plug :verify_webhook_token
  end

  pipeline :backoffice_auth do
    plug :browser
    plug :ensure_backoffice_authenticated
  end

  scope "/", BrainWeb do
    pipe_through [:api, :webhook_auth]

    post "/webhook/whatsapp", WebhookController, :create
  end

  scope "/backoffice", BrainWeb do
    pipe_through :backoffice_login

    get "/login", BackofficeSessionController, :new
    post "/login", BackofficeSessionController, :create
    get "/logout", BackofficeSessionController, :delete
    delete "/logout", BackofficeSessionController, :delete
  end

  scope "/backoffice", BrainWeb do
    pipe_through :backoffice_auth

    live "/", BackofficeLive, :index
    live "/groups", BackofficeLive, :index

    post "/groups/approve", BackofficeActionController, :approve
    post "/groups/block", BackofficeActionController, :block
    post "/groups/unblock", BackofficeActionController, :unblock
    post "/groups/delete", BackofficeActionController, :delete
  end

  pipeline :backoffice_login do
    plug :browser
  end

  defp verify_webhook_token(conn, _opts) do
    secret =
      Application.get_env(:brain, :webhook_secret) || raise "WEBHOOK_SECRET must be set in config"

    provided =
      conn.req_headers
      |> Enum.find_value(fn
        {"x-webhook-token", val} -> val
        {"authorization", "Bearer " <> val} -> val
        _ -> nil
      end)

    case provided do
      nil ->
        unauthorized(conn)

      token ->
        if Plug.Crypto.secure_compare(token, secret) do
          conn
        else
          unauthorized(conn)
        end
    end
  end

  defp unauthorized(conn) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(401, ~s({"error":"unauthorized"}))
    |> Plug.Conn.halt()
  end

  defp ensure_backoffice_authenticated(conn, _opts) do
    if get_session(conn, :backoffice_user) do
      conn
    else
      conn
      |> Phoenix.Controller.redirect(to: "/backoffice/login")
      |> Plug.Conn.halt()
    end
  end

  def put_csp_header(conn, _opts \\ []) do
    csp =
      """
        default-src 'self';
        script-src 'self';
        style-src 'self' 'unsafe-inline';
        img-src 'self' data:;
        font-src 'self';
        connect-src 'self';
        frame-ancestors 'none';
        base-uri 'self';
        form-action 'self';
      """
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    put_resp_header(conn, "content-security-policy", csp)
  end
end
