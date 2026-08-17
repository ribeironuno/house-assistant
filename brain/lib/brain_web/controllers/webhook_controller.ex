defmodule BrainWeb.WebhookController do
  use BrainWeb, :controller
  require Logger

  alias Brain.Groups
  alias Brain.WhatsApp.BridgeClient
  alias Brain.Workers.CommandWorker

  @moduledoc """
  Receives incoming WhatsApp events forwarded by the Bridge and dispatches
  them to `Brain.Workers.CommandWorker` for async processing.

  ## Webhook payload (POST /webhook/whatsapp)

      %{
        "event"    => "group_join",            # optional: bot added to a group
        "group_id" => "<group JID>",
        "sender"   => "<sender JID>",
        "text"     => "<message body>",
        "media"    => %{"data" => ..., "mimetype" => ...},  # optional
        "from_me"  => true | false,
        "timestamp" => <unix ts>,
        "message_id" => "<whatsapp message id>"  # for idempotency
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

  def create(conn, %{"event" => "group_join", "group_id" => group_id} = params) do
    Logger.info("[Brain] Bot added to group #{group_id}")
    opts = extract_group_opts(params)

    case Groups.handle_join(group_id, opts) do
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
    opts = extract_group_opts(params)
    message_id = Map.get(params, "message_id")

    with_group_gating(group_id, text, sender, opts, message_id, media, fn ->
      Logger.info(
        "[Brain] Received media in group #{group_id} from #{sender} (#{Map.get(media, "mimetype")})"
      )

      case Brain.ShoppingList.InvoiceProcessor.process_media(media, group_id, sender) do
        {:reply, reply_text} ->
          BridgeClient.send_message(group_id, reply_text)

        :ignore ->
          if text != "" do
            enqueue_command(group_id, sender, text, "text", "", message_id)
          end
      end
    end)

    json(conn, %{status: "ok"})
  end

  def create(conn, %{"group_id" => group_id, "sender" => sender, "text" => text} = params) do
    opts = extract_group_opts(params)
    message_id = Map.get(params, "message_id")

    with_group_gating(group_id, text, sender, opts, message_id, nil, fn ->
      Logger.info(
        "[Brain] Received message in group #{group_id} from #{sender}: #{inspect(text)}"
      )

      enqueue_command(group_id, sender, text, "text", "", message_id)
    end)

    json(conn, %{status: "ok"})
  end

  # Fallback: catches malformed payloads that don't match the expected shape.
  def create(conn, params) do
    Logger.warning("[Brain] Webhook payload with unexpected structure: #{inspect(params)}")
    json(conn, %{status: "ignored"})
  end

  defp with_group_gating(group_id, text, sender, opts, _message_id, _media, callback) do
    case Groups.handle_message(group_id, text, sender, opts) do
      :proceed ->
        callback.()

      {:reply, reply_text} ->
        BridgeClient.send_message(group_id, reply_text)

      {:leave, reply_text} ->
        BridgeClient.send_message(group_id, reply_text)
        Groups.request_leave(group_id)

      :ignore ->
        :ok
    end
  end

  defp extract_group_opts(params) do
    case Map.get(params, "group_name") || Map.get(params, "name") do
      name when is_binary(name) and name != "" -> %{name: name}
      _ -> %{}
    end
  end

  defp enqueue_command(group_id, sender, message, message_type, media_base64, message_id) do
    args = %{
      "message_id" =>
        message_id || "#{group_id}-#{sender}-#{DateTime.to_unix(DateTime.utc_now())}",
      "payload" => %{
        "group_id" => group_id,
        "sender" => sender,
        "message" => message,
        "message_type" => message_type,
        "media_base64" => media_base64,
        "timestamp" => DateTime.to_unix(DateTime.utc_now())
      }
    }

    Oban.insert(Brain.Oban, CommandWorker.new(args))
  end
end
