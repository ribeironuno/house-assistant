defmodule BrainWeb.BackofficeActionControllerTest do
  use BrainWeb.ConnCase, async: false

  alias Brain.Groups
  alias Brain.Repo
  alias Brain.Groups.Group

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Repo.delete_all(Group)
    :ok
  end

  describe "POST /backoffice/groups/delete" do
    test "deletes a group and redirects to /backoffice", %{conn: conn} do
      Groups.handle_join("group_del@g.us", %{group_name: "Test Group"})
      assert Repo.get(Group, "group_del@g.us")

      conn =
        conn
        |> init_test_session(%{backoffice_user: "admin"})
        |> post("/backoffice/groups/delete", %{"group_id" => "group_del@g.us"})

      assert redirected_to(conn) == "/backoffice"
      refute Repo.get(Group, "group_del@g.us")
    end
  end

  describe "POST /backoffice/groups/approve" do
    test "approves a waiting_approval group", %{conn: conn} do
      Groups.handle_join("group_app@g.us")

      conn =
        conn
        |> init_test_session(%{backoffice_user: "admin"})
        |> post("/backoffice/groups/approve", %{"group_id" => "group_app@g.us"})

      assert redirected_to(conn) == "/backoffice"
      assert Repo.get(Group, "group_app@g.us").status == "pending"
    end
  end
end
