defmodule Brain.Commands do
  @moduledoc """
  Routes incoming Portuguese text commands to the relevant Brain context.

  This module intentionally stays free of HTTP and WhatsApp concerns. It is the
  stable entry point used by the webhook while shopping-list and reminder logic
  live in their own context modules.
  """

  alias Brain.Reminders
  alias Brain.ShoppingList

  @help_text """
             [BOT] Comandos que conheço:
             🛒 Compras
             - adiciona <item> ou adiciona <item>, <item>
             - remove <item>
             - lista
             - limpar lista

             🔔 Lembretes
             - lembrar de <tarefa> logo
             - lembrar de <tarefa> amanhã
             - lembrar de <tarefa> daqui a N minutos/horas/dias/semanas

             ❔ Ajuda
             - ajuda
             """
             |> String.trim_trailing()

  def handle(text, sender, group_id \\ nil)

  def handle(text, sender, group_id) when is_binary(text) do
    trimmed_raw = String.trim(text)
    trimmed_lower = String.downcase(trimmed_raw)

    if bot_reply?(trimmed_lower) do
      :ignore
    else
      route(trimmed_raw, trimmed_lower, sender, group_id)
    end
  end

  def handle(_text, _sender, _group_id), do: :ignore

  defp route(trimmed_raw, trimmed_lower, sender, group_id, llm_attempted? \\ false) do
    cond do
      help_command?(trimmed_lower) ->
        {:reply, @help_text}

      reminder_command?(trimmed_lower) ->
        Reminders.schedule_from_text(trimmed_raw, sender, group_id)

      trimmed_lower in ["lista", "mostrar lista", "ver lista", "list", "show list"] ->
        ShoppingList.list()

      trimmed_lower in ["limpar", "limpar lista", "clear", "clear list"] ->
        ShoppingList.clear()

      String.starts_with?(trimmed_lower, "adicionar") ->
        trimmed_raw
        |> extract_argument("adicionar")
        |> ShoppingList.add(sender)

      String.starts_with?(trimmed_lower, "adiciona") ->
        trimmed_raw
        |> extract_argument("adiciona")
        |> ShoppingList.add(sender)

      String.starts_with?(trimmed_lower, "add") ->
        trimmed_raw
        |> extract_argument("add")
        |> ShoppingList.add(sender)

      String.starts_with?(trimmed_lower, "remover") ->
        trimmed_raw
        |> extract_argument("remover")
        |> ShoppingList.remove()

      String.starts_with?(trimmed_lower, "remove") ->
        trimmed_raw
        |> extract_argument("remove")
        |> ShoppingList.remove()

      true and not llm_attempted? ->
        fallback_to_llm(trimmed_raw, sender, group_id)

      true ->
        :ignore
    end
  end

  defp fallback_to_llm(trimmed_raw, sender, group_id) do
    case Brain.LLM.CommandInterpreter.interpret(trimmed_raw) do
      {:ok, canonical_command} ->
        route(canonical_command, String.downcase(canonical_command), sender, group_id, true)

      :ignore ->
        :ignore
    end
  end

  defp bot_reply?(trimmed_lower) do
    String.starts_with?(trimmed_lower, [
      "[bot]",
      "✅",
      "🗑️",
      "🛒",
      "🧹",
      "🔔",
      "por favor",
      "o item",
      "não foi",
      "lembrete"
    ])
  end

  defp reminder_command?(trimmed_lower) do
    String.starts_with?(trimmed_lower, [
      "lembrar de",
      "lembrar-me de",
      "lembra de",
      "lembra-me de",
      "lembra-nos de"
    ])
  end

  defp help_command?(trimmed_lower) do
    trimmed_lower in ["ajuda", "help", "comandos", "ver comandos"]
  end

  defp extract_argument(raw_text, command_prefix) do
    offset = String.length(command_prefix)
    String.slice(raw_text, offset..-1//1) |> String.trim()
  end
end
