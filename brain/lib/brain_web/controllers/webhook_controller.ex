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
  Handles a `group_join` event: the bot was added to a group, so it introduces
  itself and asks the group to reply "sim" or "não".
  """
  def create(conn, %{"event" => "group_join", "group_id" => group_id}) do
    Logger.info("[Brain] Bot added to group #{group_id}")

    case Groups.handle_join(group_id) do
      {:reply, reply_text} -> BridgeClient.send_message(group_id, reply_text)
      _ -> :ok
    end

    json(conn, %{status: "ok"})
  end

  @doc """
  Handles an incoming message with media (invoices/receipts).
  """
  def create(
        conn,
        %{"group_id" => group_id, "sender" => sender, "media" => %{"data" => _data} = media} =
          params
      )
      when not is_nil(media) do
    text = Map.get(params, "text", "")

    case Groups.handle_message(group_id, text, sender) do
      :proceed ->
        Logger.info(
          "[Brain] Received media in group #{group_id} from #{sender} (#{Map.get(media, "mimetype")})"
        )

        result = Brain.ShoppingList.InvoiceProcessor.process_media(media, group_id, sender)

        case result do
          {:reply, reply_text} ->
            BridgeClient.send_message(group_id, reply_text)

          :ignore ->
            if text != "" do
              dispatch_text(group_id, text, sender)
            end
        end

      {:reply, reply_text} ->
        BridgeClient.send_message(group_id, reply_text)

      {:leave, reply_text} ->
        BridgeClient.send_message(group_id, reply_text)
        Groups.request_leave(group_id)

      :ignore ->
        :ok
    end

    json(conn, %{status: "ok"})
  end

  def create(conn, %{"group_id" => group_id, "sender" => sender, "text" => text}) do
    dispatch_text(group_id, text, sender)
    json(conn, %{status: "ok"})
  end

  # Fallback: catches malformed payloads that don't match the expected shape.
  def create(conn, params) do
    Logger.warning("[Brain] Webhook payload with unexpected structure: #{inspect(params)}")
    json(conn, %{status: "ignored"})
  end

  defp dispatch_text(group_id, text, sender) do
    case Groups.handle_message(group_id, text, sender) do
      :proceed ->
        Logger.info(
          "[Brain] Received message in group #{group_id} from #{sender}: #{inspect(text)}"
        )

        case Brain.Commands.handle(text, sender, group_id) do
          {:reply, reply_text} ->
            BridgeClient.send_message(group_id, reply_text)

          :ignore ->
            :ok
        end

      {:reply, reply_text} ->
        BridgeClient.send_message(group_id, reply_text)

      {:leave, reply_text} ->
        BridgeClient.send_message(group_id, reply_text)
        Groups.request_leave(group_id)

      :ignore ->
        :ok
    end
  end
end
