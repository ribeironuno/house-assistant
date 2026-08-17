defmodule Brain.Workers.CommandWorker do
  use Oban.Worker, queue: :commands, max_attempts: 3

  alias Brain.Repo
  alias Brain.Groups
  alias Brain.Commands
  alias Brain.ProcessedMessage
  alias Brain.WhatsApp.BridgeClient

  @impl true
  def perform(%Oban.Job{args: args}) do
    message_id = args["message_id"]
    payload = args["payload"]

    case Repo.insert(%ProcessedMessage{message_id: message_id}, on_conflict: :nothing) do
      {:ok, _} ->
        process_command(payload)

      {:error, _} ->
        {:ok, :duplicate}
    end
  end

  defp process_command(payload) do
    group_id = payload["group_id"]
    sender = payload["sender"]
    message = payload["message"]
    _message_type = payload["message_type"]
    _media_base64 = payload["media_base64"]

    case Groups.get_group(group_id) do
      %Groups.Group{status: "active"} = _group ->
        case Commands.handle(message, sender, group_id) do
          {:reply, reply_text} ->
            BridgeClient.send_message(group_id, reply_text)
            {:ok, :processed}

          :ignore ->
            {:ok, :ignored}
        end

      %Groups.Group{status: "pending"} = group ->
        case Groups.handle_pending_activation(group.group_id, message) do
          {:reply, reply_text} ->
            BridgeClient.send_message(group_id, reply_text)
            {:ok, :processed}

          {:leave, reply_text} ->
            BridgeClient.send_message(group_id, reply_text)
            Groups.request_leave(group_id)
            {:ok, :processed}
        end

      _ ->
        {:ok, :ignored}
    end
  end
end
