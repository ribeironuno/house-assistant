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
      do_post(bridge_url("send"), %{to: group_id, text: text})
    end
  end

  @doc """
  Asks the Bridge to leave a WhatsApp group.
  """
  def leave_group(group_id) do
    if Application.get_env(:brain, :send_outgoing_messages, true) == false do
      Logger.info("[Brain] Outgoing messages disabled by config: leave group #{group_id}")
      :ok
    else
      do_post(bridge_url("leave"), %{group_id: group_id})
    end
  end

  defp do_post(url, body) do
    auth_token = Application.get_env(:brain, :bridge_auth_token)

    Logger.info("[Brain] POSTing to bridge #{url}: #{inspect(body)}")

    headers =
      if auth_token && auth_token != "" do
        [{"authorization", "Bearer #{auth_token}"}]
      else
        []
      end

    case Req.post(url,
           json: body,
           headers: headers,
           connect_options: [timeout: 5_000],
           receive_timeout: 15_000
         ) do
      {:ok, %Req.Response{status: 200}} ->
        Logger.info("[Brain] Bridge request confirmed")
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

  defp bridge_url(endpoint) do
    env_key = if endpoint == "send", do: "BRIDGE_SEND_URL", else: "BRIDGE_LEAVE_URL"

    default_bridge_url =
      if System.get_env("PHX_SERVER") == "true",
        do: "http://bridge:3000/#{endpoint}",
        else: "http://localhost:3000/#{endpoint}"

    System.get_env(env_key, default_bridge_url)
  end
end
