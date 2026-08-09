defmodule Brain.WhatsApp.BridgeClient do
  require Logger

  @moduledoc """
  HTTP client for sending outgoing WhatsApp messages through the Bridge.
  """

  @doc """
  Sends a WhatsApp message to a group or chat JID through the Bridge.
  """
  def send_message(group_id, text) do
    if Application.get_env(:brain, :send_outgoing_messages, true) == false do
      Logger.info(
        "[Brain] Outgoing messages disabled by config: #{inspect(%{to: group_id, text: text})}"
      )

      :ok
    else
      do_send_message(group_id, text)
    end
  end

  defp do_send_message(group_id, text) do
    bridge_url = bridge_send_url()
    auth_token = Application.get_env(:brain, :bridge_auth_token)

    Logger.info("[Brain] Sending message '#{text}' to group [#{group_id}] via #{bridge_url}")

    headers =
      if auth_token && auth_token != "" do
        [{"authorization", "Bearer #{auth_token}"}]
      else
        []
      end

    case Req.post(bridge_url,
           json: %{to: group_id, text: text},
           headers: headers,
           connect_options: [timeout: 5_000],
           receive_timeout: 15_000
         ) do
      {:ok, %Req.Response{status: 200}} ->
        Logger.info("[Brain] Message confirmed by the Bridge")
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("[Brain] Bridge responded with HTTP #{status}: #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, exception} ->
        Logger.error(
          "[Brain] Failed to communicate with the Bridge endpoint: #{inspect(exception)}"
        )

        {:error, exception}
    end
  end

  defp bridge_send_url do
    default_bridge_url =
      if System.get_env("PHX_SERVER") == "true",
        do: "http://bridge:3000/send",
        else: "http://localhost:3000/send"

    System.get_env("BRIDGE_SEND_URL", default_bridge_url)
  end
end
