defmodule BrainWeb.BackofficeSessionControllerTest do
  use BrainWeb.ConnCase, async: false

  describe "GET /backoffice/login" do
    test "renders login form for unauthenticated users", %{conn: conn} do
      conn = get(conn, "/backoffice/login")
      assert html_response(conn, 200) =~ "Backoffice Login"
      assert html_response(conn, 200) =~ ~s(<input type="text" id="user" name="user")
      assert html_response(conn, 200) =~ ~s(<input type="password" id="pass" name="pass")
    end

    test "redirects to /backoffice if already logged in", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{backoffice_user: "admin"})
        |> get("/backoffice/login")

      assert redirected_to(conn) == "/backoffice"
    end
  end

  describe "POST /backoffice/login" do
    test "authenticates with valid credentials and redirects to /backoffice", %{conn: conn} do
      conn = post(conn, "/backoffice/login", %{"user" => "admin", "pass" => "admin"})
      assert redirected_to(conn) == "/backoffice"
      assert get_session(conn, :backoffice_user) == "admin"
    end

    test "rejects invalid credentials and redirects back with error", %{conn: conn} do
      conn = post(conn, "/backoffice/login", %{"user" => "admin", "pass" => "wrongpass"})
      assert redirected_to(conn) == "/backoffice/login?error=Invalid+credentials"
      refute get_session(conn, :backoffice_user)
    end
  end

  describe "GET /backoffice/logout" do
    test "clears session and redirects to /backoffice/login", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{backoffice_user: "admin"})
        |> get("/backoffice/logout")

      assert redirected_to(conn) == "/backoffice/login"
      refute get_session(conn, :backoffice_user)
    end
  end
end
