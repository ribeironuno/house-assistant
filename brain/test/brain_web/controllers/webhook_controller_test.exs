defmodule BrainWeb.WebhookControllerTest do
  use BrainWeb.ConnCase

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Brain.Repo)
  end

  test "POST /webhook/whatsapp handles unrecognized message without reply", %{conn: conn} do
    payload = %{
      "group_id" => "12345@g.us",
      "sender" => "67890@s.whatsapp.net",
      "text" => "Olá mundo"
    }

    conn = post(conn, ~p"/webhook/whatsapp", payload)
    assert json_response(conn, 200) == %{"status" => "ok"}
  end

  test "POST /webhook/whatsapp processes from_me:true messages (human commands from owner's phone)",
       %{conn: conn} do
    payload = %{
      "group_id" => "12345@g.us",
      "sender" => "67890@s.whatsapp.net",
      "text" => "adiciona leite",
      "from_me" => true
    }

    conn = post(conn, ~p"/webhook/whatsapp", payload)
    assert json_response(conn, 200) == %{"status" => "ok"}
    assert length(Brain.Repo.all(Brain.ShoppingItem)) == 1
  end

  test "POST /webhook/whatsapp ignores [BOT] prefixed messages to prevent echo loops", %{
    conn: conn
  } do
    payload = %{
      "group_id" => "12345@g.us",
      "sender" => "67890@s.whatsapp.net",
      "text" => "[BOT] ✅ Adicionado: leite",
      "from_me" => true
    }

    conn = post(conn, ~p"/webhook/whatsapp", payload)
    assert json_response(conn, 200) == %{"status" => "ok"}
    assert Brain.Repo.all(Brain.ShoppingItem) == []
  end

  test "POST /webhook/whatsapp processes 'adiciona leite' command", %{conn: conn} do
    payload = %{
      "group_id" => "12345@g.us",
      "sender" => "67890@s.whatsapp.net",
      "text" => "adiciona leite"
    }

    conn = post(conn, ~p"/webhook/whatsapp", payload)
    assert json_response(conn, 200) == %{"status" => "ok"}
    assert length(Brain.Repo.all(Brain.ShoppingItem)) == 1
  end

  test "POST /webhook/whatsapp creates reminders", %{conn: conn} do
    payload = %{
      "group_id" => "12345@g.us",
      "sender" => "67890@s.whatsapp.net",
      "text" => "lembrar de pagar scouts daqui a 3 dias"
    }

    conn = post(conn, ~p"/webhook/whatsapp", payload)
    assert json_response(conn, 200) == %{"status" => "ok"}

    [reminder] = Brain.Repo.all(Brain.Reminder)
    assert reminder.text == "pagar scouts"
    assert reminder.group_id == "12345@g.us"
  end
end
