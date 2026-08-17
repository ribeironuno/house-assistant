defmodule BrainWeb.BackofficeSessionController do
  use BrainWeb, :controller
  require Logger
  alias Bcrypt

  def new(conn, params) do
    if get_session(conn, :backoffice_user) do
      redirect(conn, to: "/backoffice")
    else
      error = params["error"]
      csrf_token = Plug.CSRFProtection.get_csrf_token()

      html(conn, """
      <!DOCTYPE html>
      <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>Backoffice Login</title>
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f7fb; display: flex; align-items: center; justify-content: center; height: 100vh; }
            .login-card { background: white; padding: 2.5rem; border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.08); width: 100%; max-width: 400px; }
            h2 { margin-bottom: 1.5rem; color: #1a1a1a; font-size: 1.5rem; text-align: center; }
            .form-group { margin-bottom: 1.2rem; }
            label { display: block; margin-bottom: 0.4rem; font-size: 0.9rem; color: #4a5568; font-weight: 500; }
            input[type="text"], input[type="password"] { width: 100%; padding: 0.6rem 0.8rem; border: 1px solid #cbd5e0; border-radius: 4px; font-size: 1rem; }
            input[type="text"]:focus, input[type="password"]:focus { outline: none; border-color: #3182ce; box-shadow: 0 0 0 3px rgba(49,130,206,0.15); }
            button { width: 100%; padding: 0.75rem; background: #3182ce; color: white; border: none; border-radius: 4px; font-size: 1rem; font-weight: 600; cursor: pointer; margin-top: 0.5rem; }
            button:hover { background: #2b6cb0; }
            .error-msg { background: #fed7d7; border: 1px solid #feb2b2; color: #9b2c2c; padding: 0.6rem 0.8rem; border-radius: 4px; margin-bottom: 1rem; font-size: 0.9rem; }
          </style>
        </head>
        <body>
          <div class="login-card">
            <h2>Backoffice Login</h2>
            #{if error, do: "<div class=\"error-msg\">#{Plug.HTML.html_escape(error)}</div>", else: ""}
            <form action="/backoffice/login" method="post">
              <input type="hidden" name="_csrf_token" value="#{csrf_token}" />
              <div class="form-group">
                <label for="user">Username</label>
                <input type="text" id="user" name="user" required autofocus />
              </div>
              <div class="form-group">
                <label for="pass">Password</label>
                <input type="password" id="pass" name="pass" required />
              </div>
              <button type="submit">Sign In</button>
            </form>
          </div>
        </body>
      </html>
      """)
    end
  end

  def create(conn, %{"user" => user, "pass" => pass}) do
    expected_user = Application.get_env(:brain, :backoffice_user)
    expected_pass_hash = Application.get_env(:brain, :backoffice_pass_hash)

    unless expected_user && expected_pass_hash do
      Logger.error("[Backoffice] backoffice_user and backoffice_pass_hash must be set in config")
      redirect(conn, to: "/backoffice/login?error=Server+misconfigured")
    else
      if Plug.Crypto.secure_compare(user, expected_user) and
           Bcrypt.verify_pass(pass, expected_pass_hash) do
        conn
        |> put_session(:backoffice_user, user)
        |> configure_session(renew: true)
        |> redirect(to: "/backoffice")
      else
        redirect(conn, to: "/backoffice/login?error=Invalid+credentials")
      end
    end
  end

  def create(conn, _params) do
    redirect(conn, to: "/backoffice/login?error=Invalid+credentials")
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/backoffice/login")
  end
end
