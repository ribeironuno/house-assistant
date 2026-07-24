defmodule BrainWeb.WebhookController do
  use BrainWeb, :controller
  require Logger

  def create(conn, %{"group_id" => group_id, "sender" => sender, "text" => text}) do
    Logger.info("[Brain] Received message in group #{group_id} from #{sender}: #{inspect(text)}")

    trimmed_text = text |> String.trim() |> String.downcase()

    if trimmed_text == "ping" do
      send_reply(group_id, "pong")
    end

    json(conn, %{status: "ok"})
  end

  def create(conn, params) do
    Logger.warning("[Brain] Received webhook payload with unexpected structure: #{inspect(params)}")
    json(conn, %{status: "ignored"})
  end

  defp send_reply(group_id, reply_text) do
    bridge_url = System.get_env("BRIDGE_SEND_URL", "http://bridge:3000/send")
    Logger.info("[Brain] Sending reply '#{reply_text}' to group [#{group_id}] via #{bridge_url}")

    case Req.post(bridge_url, json: %{to: group_id, text: reply_text}) do
      {:ok, %Req.Response{status: 200}} ->
        Logger.info("[Brain] Reply successfully acknowledged by bridge")

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("[Brain] Bridge returned HTTP #{status}: #{inspect(body)}")

      {:error, exception} ->
        Logger.error("[Brain] Failed to reach bridge send endpoint: #{inspect(exception)}")
    end
  end
end
