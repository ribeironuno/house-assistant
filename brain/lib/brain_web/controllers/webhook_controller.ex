defmodule BrainWeb.WebhookController do
  use BrainWeb, :controller
  require Logger

  alias Brain.Groups
  alias Brain.WhatsApp.BridgeClient

  @moduledoc """
  Receives incoming WhatsApp events forwarded by the Bridge and dispatches
  them to `Brain.Commands` for processing.

  ## Webhook payload (POST /webhook/whatsapp)

      %{
        "event"    => "group_join",            # optional: bot added to a group
        "group_id" => "<group JID>",
        "sender"   => "<sender JID>",
        "text"     => "<message body>",
        "media"    => %{"data" => ..., "mimetype" => ...},  # optional
        "from_me"  => true | false,
        "timestamp" => <unix ts>
      }

  Every incoming message is first gated by `Brain.Groups`: groups must opt in
  ("sim") before the bot processes commands. Loop prevention for bot echoes is
  handled via the `[BOT]` prefix check in `Brain.Commands`.
  """

  @doc """
  Entry point for bridge webhook events.

  Handles `group_join` events (bot added to a group), incoming messages with
  media (invoices/receipts), and plain text messages. Malformed payloads that
  don't match the expected shape are ignored.
  """
  def create(conn, params)

  def create(conn, %{"event" => "group_join", "group_id" => group_id}) do
    Logger.info("[Brain] Bot added to group #{group_id}")

    case Groups.handle_join(group_id) do
      {:reply, reply_text} -> BridgeClient.send_message(group_id, reply_text)
      _ -> :ok
    end

    json(conn, %{status: "ok"})
  end

  def create(
        conn,
        %{"group_id" => group_id, "sender" => sender, "media" => %{"data" => _data} = media} =
          params
      ) do
    text = Map.get(params, "text", "")

    with_group_gating(group_id, text, sender, fn ->
      Logger.info(
        "[Brain] Received media in group #{group_id} from #{sender} (#{Map.get(media, "mimetype")})"
      )

      case Brain.ShoppingList.InvoiceProcessor.process_media(media, group_id, sender) do
        {:reply, reply_text} ->
          BridgeClient.send_message(group_id, reply_text)

        :ignore ->
          if text != "" do
            case Brain.Commands.handle(text, sender, group_id) do
              {:reply, reply_text} -> BridgeClient.send_message(group_id, reply_text)
              :ignore -> :ok
            end
          end
      end
    end)

    json(conn, %{status: "ok"})
  end

  def create(conn, %{"group_id" => group_id, "sender" => sender, "text" => text}) do
    with_group_gating(group_id, text, sender, fn ->
      Logger.info(
        "[Brain] Received message in group #{group_id} from #{sender}: #{inspect(text)}"
      )

      case Brain.Commands.handle(text, sender, group_id) do
        {:reply, reply_text} -> BridgeClient.send_message(group_id, reply_text)
        :ignore -> :ok
      end
    end)

    json(conn, %{status: "ok"})
  end

  # Fallback: catches malformed payloads that don't match the expected shape.
  def create(conn, params) do
    Logger.warning("[Brain] Webhook payload with unexpected structure: #{inspect(params)}")
    json(conn, %{status: "ignored"})
  end

  defp with_group_gating(group_id, text, sender, callback) do
    case Groups.handle_message(group_id, text, sender) do
      :proceed ->
        callback.()

      {:reply, reply_text} ->
        BridgeClient.send_message(group_id, reply_text)

      {:leave, reply_text} ->
        BridgeClient.send_message(group_id, reply_text)
        Process.sleep(1500)
        Groups.request_leave(group_id)

      :ignore ->
        :ok
    end
  end
end
