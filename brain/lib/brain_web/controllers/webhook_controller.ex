defmodule BrainWeb.WebhookController do
  use BrainWeb, :controller
  require Logger

  @moduledoc """
  Receives incoming WhatsApp messages forwarded by the Bridge and dispatches
  them to `Brain.Commands` for processing.

  ## Webhook payload (POST /webhook/whatsapp)

      %{
        "group_id" => "<group JID>",
        "sender"   => "<sender JID>",
        "text"     => "<message body>",
        "from_me"  => true | false,
        "timestamp" => <unix ts>
      }

  All messages — including `from_me: true` ones (typed on the owner's phone) —
  are passed to `Brain.Commands.handle/2`. Loop prevention is handled there via
  the `[BOT]` prefix check, not by discarding `from_me` messages wholesale.
  """

  @doc """
  Handles an incoming webhook event from the Bridge.
  Supports text commands and media attachments (invoices/receipts).
  """
  def create(
        conn,
        %{"group_id" => group_id, "sender" => sender, "media" => %{"data" => _data} = media} =
          params
      )
      when not is_nil(media) do
    Logger.info(
      "[Brain] Media recebido no grupo #{group_id} de #{sender} (#{Map.get(media, "mimetype")})"
    )

    result = Brain.ShoppingList.InvoiceProcessor.process_media(media, sender)

    case result do
      {:reply, reply_text} ->
        Brain.WhatsApp.BridgeClient.send_message(group_id, reply_text)

      :ignore ->
        text = Map.get(params, "text", "")

        if text != "" do
          case Brain.Commands.handle(text, sender, group_id) do
            {:reply, reply_text} -> Brain.WhatsApp.BridgeClient.send_message(group_id, reply_text)
            :ignore -> :ok
          end
        end
    end

    json(conn, %{status: "ok"})
  end

  def create(conn, %{"group_id" => group_id, "sender" => sender, "text" => text}) do
    Logger.info("[Brain] Mensagem recebida no grupo #{group_id} de #{sender}: #{inspect(text)}")

    case Brain.Commands.handle(text, sender, group_id) do
      {:reply, reply_text} ->
        Brain.WhatsApp.BridgeClient.send_message(group_id, reply_text)

      :ignore ->
        :ok
    end

    json(conn, %{status: "ok"})
  end

  # Fallback: catches malformed payloads that don't match the expected shape.
  def create(conn, params) do
    Logger.warning("[Brain] Payload do webhook com estrutura inesperada: #{inspect(params)}")
    json(conn, %{status: "ignored"})
  end
end
