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
        "[Brain] Envio de mensagem desativado por configuração: #{inspect(%{to: group_id, text: text})}"
      )

      :ok
    else
      do_send_message(group_id, text)
    end
  end

  defp do_send_message(group_id, text) do
    bridge_url = bridge_send_url()

    Logger.info(
      "[Brain] A enviar mensagem '#{text}' para o grupo [#{group_id}] via #{bridge_url}"
    )

    case Req.post(bridge_url, json: %{to: group_id, text: text}) do
      {:ok, %Req.Response{status: 200}} ->
        Logger.info("[Brain] Mensagem confirmada pela ponte (Bridge)")
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("[Brain] Ponte (Bridge) respondeu com HTTP #{status}: #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, exception} ->
        Logger.error(
          "[Brain] Falha ao comunicar com o endpoint da ponte (Bridge): #{inspect(exception)}"
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
