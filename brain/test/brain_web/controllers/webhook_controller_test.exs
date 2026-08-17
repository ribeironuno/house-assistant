defmodule BrainWeb.WebhookControllerTest do
  use BrainWeb.ConnCase

  @group_id "group_1"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Brain.Repo)
  end

  test "POST /webhook/whatsapp returns 401 when WEBHOOK_SECRET is set and header is missing",
       %{conn: conn} do
    payload = %{
      "group_id" => @group_id,
      "sender" => "67890@s.whatsapp.net",
      "text" => "adiciona leite"
    }

    conn = post(conn, ~p"/webhook/whatsapp", payload)
    assert json_response(conn, 401)
  end

  test "POST /webhook/whatsapp succeeds when WEBHOOK_SECRET is set and header matches",
       %{conn: conn} do
    activate_group(@group_id)

    payload = %{
      "group_id" => @group_id,
      "sender" => "67890@s.whatsapp.net",
      "text" => "adiciona leite"
    }

    conn =
      conn
      |> put_req_header("x-webhook-token", "test-secret")
      |> post(~p"/webhook/whatsapp", payload)

    assert json_response(conn, 200) == %{"status" => "ok"}
    assert length(Brain.Repo.all(Brain.ShoppingList.Item)) == 1
  end

  test "POST /webhook/whatsapp sends intro reply and does not process commands for unknown groups",
       %{conn: conn} do
    payload = %{
      "group_id" => "unknown_group",
      "sender" => "67890@s.whatsapp.net",
      "text" => "adiciona leite"
    }

    conn =
      conn
      |> put_req_header("x-webhook-token", "test-secret")
      |> post(~p"/webhook/whatsapp", payload)

    assert json_response(conn, 200) == %{"status" => "ok"}

    assert Brain.Repo.get(Brain.Groups.Group, "unknown_group").status == "waiting_approval"
    assert Brain.Repo.all(Brain.ShoppingList.Item) == []
  end

  test "POST /webhook/whatsapp handles unrecognized message without reply", %{conn: conn} do
    activate_group(@group_id)

    payload = %{
      "group_id" => @group_id,
      "sender" => "67890@s.whatsapp.net",
      "text" => "Olá mundo"
    }

    conn =
      conn
      |> put_req_header("x-webhook-token", "test-secret")
      |> post(~p"/webhook/whatsapp", payload)

    assert json_response(conn, 200) == %{"status" => "ok"}
  end

  test "POST /webhook/whatsapp processes from_me:true messages (human commands from owner's phone)",
       %{conn: conn} do
    activate_group(@group_id)

    payload = %{
      "group_id" => @group_id,
      "sender" => "67890@s.whatsapp.net",
      "text" => "adiciona leite",
      "from_me" => true
    }

    conn =
      conn
      |> put_req_header("x-webhook-token", "test-secret")
      |> post(~p"/webhook/whatsapp", payload)

    assert json_response(conn, 200) == %{"status" => "ok"}
    assert length(Brain.Repo.all(Brain.ShoppingList.Item)) == 1
  end

  test "POST /webhook/whatsapp ignores [BOT] prefixed messages to prevent echo loops", %{
    conn: conn
  } do
    activate_group(@group_id)

    payload = %{
      "group_id" => @group_id,
      "sender" => "67890@s.whatsapp.net",
      "text" => "[BOT] ✅ Adicionado: leite",
      "from_me" => true
    }

    conn =
      conn
      |> put_req_header("x-webhook-token", "test-secret")
      |> post(~p"/webhook/whatsapp", payload)

    assert json_response(conn, 200) == %{"status" => "ok"}
    assert Brain.Repo.all(Brain.ShoppingList.Item) == []
  end

  test "POST /webhook/whatsapp processes 'adiciona leite' command", %{conn: conn} do
    activate_group(@group_id)

    payload = %{
      "group_id" => @group_id,
      "sender" => "67890@s.whatsapp.net",
      "text" => "adiciona leite"
    }

    conn =
      conn
      |> put_req_header("x-webhook-token", "test-secret")
      |> post(~p"/webhook/whatsapp", payload)

    assert json_response(conn, 200) == %{"status" => "ok"}
    assert length(Brain.Repo.all(Brain.ShoppingList.Item)) == 1
  end

  test "POST /webhook/whatsapp creates reminders", %{conn: conn} do
    activate_group(@group_id)

    payload = %{
      "group_id" => @group_id,
      "sender" => "67890@s.whatsapp.net",
      "text" => "lembrar de pagar scouts daqui a 3 dias"
    }

    conn =
      conn
      |> put_req_header("x-webhook-token", "test-secret")
      |> post(~p"/webhook/whatsapp", payload)

    assert json_response(conn, 200) == %{"status" => "ok"}

    [reminder] = Brain.Repo.all(Brain.Reminders.Reminder)
    assert reminder.text == "pagar scouts"
    assert reminder.group_id == @group_id
  end

  test "POST /webhook/whatsapp processes media payload", %{conn: conn} do
    activate_group(@group_id)

    payload = %{
      "group_id" => @group_id,
      "sender" => "67890@s.whatsapp.net",
      "text" => "",
      "media" => %{
        "mimetype" => "image/jpeg",
        "data" => "base64datahere"
      }
    }

    conn =
      conn
      |> put_req_header("x-webhook-token", "test-secret")
      |> post(~p"/webhook/whatsapp", payload)

    assert json_response(conn, 200) == %{"status" => "ok"}
  end

  defp activate_group(group_id) do
    Brain.Groups.register_pending(group_id)
    Brain.Groups.add_admin(group_id, "67890@s.whatsapp.net")
    Brain.Groups.activate(group_id)
  end
end
