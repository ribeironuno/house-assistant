defmodule BrainWeb.WebhookControllerTest do
  use BrainWeb.ConnCase

  test "POST /webhook/whatsapp handles non-ping messages without sending reply", %{conn: conn} do
    payload = %{
      "group_id" => "12345@g.us",
      "sender" => "67890@s.whatsapp.net",
      "text" => "Hello world"
    }

    conn = post(conn, ~p"/webhook/whatsapp", payload)
    assert json_response(conn, 200) == %{"status" => "ok"}
  end

  test "POST /webhook/whatsapp handles 'ping' message", %{conn: conn} do
    payload = %{
      "group_id" => "12345@g.us",
      "sender" => "67890@s.whatsapp.net",
      "text" => " ping "
    }

    # Req.post will fail internally in test because bridge is not running, but WebhookController handles errors gracefully
    conn = post(conn, ~p"/webhook/whatsapp", payload)
    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
