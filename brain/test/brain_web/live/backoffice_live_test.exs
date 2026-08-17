defmodule BrainWeb.BackofficeLiveTest do
  use BrainWeb.ConnCase, async: false

  alias Brain.Groups
  alias Brain.Repo
  alias Brain.Groups.Group

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Repo.delete_all(Group)
    :ok
  end

  describe "BackofficeLive at /backoffice" do
    test "redirects unauthenticated users to /backoffice/login", %{conn: conn} do
      conn = get(conn, "/backoffice")
      assert redirected_to(conn) == "/backoffice/login"
    end

    test "renders group management page for logged-in user with group name", %{conn: conn} do
      Groups.handle_join("123@g.us", %{group_name: "Os Amigos"})

      conn =
        conn
        |> init_test_session(%{backoffice_user: "admin"})
        |> get("/backoffice")

      html = html_response(conn, 200)
      assert html =~ "Group Management"
      assert html =~ "Os Amigos"
      assert html =~ "123@g.us"
      assert html =~ "waiting_approval"
      assert html =~ "Approve"
    end
  end
end
