defmodule Brain.Commands do
  @moduledoc """
  Isolated command parser and executor for the house assistant.

  All commands and responses are in Portuguese. This module is intentionally
  kept free of HTTP or WhatsApp concerns so it can be tested in isolation and
  replaced with an LLM-based parser in a future phase.

  ## Supported commands (case-insensitive)

  | Input                             | Action                        |
  |-----------------------------------|-------------------------------|
  | `adiciona <item>` / `adicionar`   | Add item to the shopping list |
  | `remove <item>` / `remover`       | Remove item by substring match|
  | `lista` / `ver lista` / `mostrar lista` | Show active items       |
  | `limpar` / `limpar lista`         | Clear all active items        |
  | `ajuda` / `help` / `comandos`     | Show known commands           |

  ## Return values

  - `{:reply, text}` — a response string to be sent back to the WhatsApp group.
    All reply strings are prefixed with `[BOT]` so the bridge can identify and
    discard the echo event it receives when the same WhatsApp account is used
    for both the bot and the owner's phone.
  - `:ignore` — the message is unrecognised or is a bot echo; no reply is sent.

  ## Loop prevention

  Any message whose downcased text starts with `[bot]` is immediately returned
  as `:ignore`. This prevents the brain from reacting to its own replies if
  they somehow bypass the bridge-level filter.
  """

  @doc """
  Ponto de entrada principal para analisar e executar comandos de texto.

  Retorna `{:reply, texto_resposta}` ou `:ignore`.
  """

  import Ecto.Query
  alias Brain.Repo
  alias Brain.Reminder
  alias Brain.ShoppingItem

  @lisbon_tz "Europe/Lisbon"

  @help_text """
             [BOT] Comandos que conheço:
             🛒 Compras
             - adiciona <item>
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
      cond do
        help_command?(trimmed_lower) ->
          {:reply, @help_text}

        reminder_command?(trimmed_lower) ->
          handle_reminder(trimmed_raw, sender, group_id)

        trimmed_lower in ["lista", "mostrar lista", "ver lista", "list", "show list"] ->
          handle_list()

        trimmed_lower in ["limpar", "limpar lista", "clear", "clear list"] ->
          handle_clear()

        String.starts_with?(trimmed_lower, "adicionar") ->
          item_text = extract_argument(trimmed_raw, "adicionar")
          handle_add(item_text, sender)

        String.starts_with?(trimmed_lower, "adiciona") ->
          item_text = extract_argument(trimmed_raw, "adiciona")
          handle_add(item_text, sender)

        String.starts_with?(trimmed_lower, "add") ->
          item_text = extract_argument(trimmed_raw, "add")
          handle_add(item_text, sender)

        String.starts_with?(trimmed_lower, "remover") ->
          item_text = extract_argument(trimmed_raw, "remover")
          handle_remove(item_text)

        String.starts_with?(trimmed_lower, "remove") ->
          item_text = extract_argument(trimmed_raw, "remove")
          handle_remove(item_text)

        true ->
          :ignore
      end
    end
  end

  def handle(_text, _sender, _group_id), do: :ignore

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

  defp handle_reminder(_raw_text, _sender, nil) do
    {:reply, "[BOT] Não consigo guardar um lembrete sem saber em que grupo devo responder."}
  end

  defp handle_reminder(raw_text, sender, group_id) do
    raw_text
    |> extract_reminder_body()
    |> parse_reminder(DateTime.utc_now())
    |> case do
      {:ok, reminder_text, remind_at} ->
        create_reminder(reminder_text, remind_at, sender, group_id)

      {:error, :missing_text} ->
        {:reply,
         "[BOT] Por favor diz o que queres que eu lembre, ex: 'lembrar de pagar scouts daqui a 3 dias'."}

      {:error, :missing_time} ->
        {:reply, "[BOT] Por favor diz quando queres o lembrete, ex: 'logo' ou 'daqui a 3 dias'."}
    end
  end

  defp extract_reminder_body(raw_text) do
    String.replace(
      raw_text,
      ~r/^\s*(lembrar(?:-me)?|lembra(?:-me)?|lembra(?:-nos)?)\s+de\s+/iu,
      "",
      global: false
    )
    |> String.trim()
  end

  defp parse_reminder("", _now), do: {:error, :missing_text}

  defp parse_reminder(body, now) do
    cond do
      match =
          Regex.run(~r/\bdaqui\s+a\s+(\d+)\s+(minutos?|mins?|horas?|dias?|semanas?)\b/iu, body) ->
        [phrase, amount_text, unit] = match
        reminder_text = remove_time_phrase(body, phrase)

        remind_at =
          DateTime.add(now, duration_in_seconds(String.to_integer(amount_text), unit), :second)

        validate_reminder_text(reminder_text, remind_at)

      Regex.match?(~r/\blogo\b/iu, body) ->
        reminder_text = remove_time_phrase(body, ~r/\blogo\b/iu)
        remind_at = DateTime.add(now, 30 * 60, :second)
        validate_reminder_text(reminder_text, remind_at)

      Regex.match?(~r/\bamanh[ãa]\b/iu, body) ->
        reminder_text = remove_time_phrase(body, ~r/\bamanh[ãa]\b/iu)
        remind_at = DateTime.add(now, 24 * 60 * 60, :second)
        validate_reminder_text(reminder_text, remind_at)

      true ->
        {:error, :missing_time}
    end
  end

  defp duration_in_seconds(amount, unit) do
    case String.downcase(unit) do
      unit when unit in ["minuto", "minutos", "min", "mins"] -> amount * 60
      unit when unit in ["hora", "horas"] -> amount * 60 * 60
      unit when unit in ["dia", "dias"] -> amount * 24 * 60 * 60
      unit when unit in ["semana", "semanas"] -> amount * 7 * 24 * 60 * 60
    end
  end

  defp remove_time_phrase(body, phrase) when is_binary(phrase) do
    body
    |> String.replace(phrase, "", global: false)
    |> clean_reminder_text()
  end

  defp remove_time_phrase(body, %Regex{} = regex) do
    body
    |> String.replace(regex, "", global: false)
    |> clean_reminder_text()
  end

  defp clean_reminder_text(text) do
    text
    |> String.trim()
    |> String.trim_trailing(".")
    |> String.trim_trailing(",")
    |> String.trim()
  end

  defp validate_reminder_text("", _remind_at), do: {:error, :missing_text}

  defp validate_reminder_text(reminder_text, remind_at),
    do: {:ok, reminder_text, DateTime.truncate(remind_at, :second)}

  defp create_reminder(reminder_text, remind_at, sender, group_id) do
    changeset =
      Reminder.changeset(%Reminder{}, %{
        text: reminder_text,
        group_id: group_id,
        created_by: sender,
        remind_at: remind_at
      })

    case Repo.insert(changeset) do
      {:ok, reminder} ->
        {:reply, format_reminder_confirmation(reminder)}

      {:error, _changeset} ->
        {:reply, "[BOT] Não foi possível guardar o lembrete."}
    end
  end

  defp format_reminder_confirmation(reminder) do
    """
    [BOT] 🔔 Lembrete guardado!
    Título: #{reminder.text}
    Data: #{format_remind_at(reminder.remind_at)}
    Falta: #{format_time_remaining(reminder.remind_at)}
    """
    |> String.trim_trailing()
  end

  defp format_remind_at(remind_at_utc) do
    remind_at_utc
    |> DateTime.shift_zone!(@lisbon_tz)
    |> Calendar.strftime("%d/%m/%Y às %H:%M")
  end

  defp format_time_remaining(remind_at_utc) do
    diff_seconds = DateTime.diff(remind_at_utc, DateTime.utc_now(), :second)

    cond do
      diff_seconds <= 0 ->
        "agora mesmo"

      diff_seconds < 60 ->
        "menos de 1 minuto"

      diff_seconds < 3600 ->
        pluralize(div(diff_seconds, 60), "minuto", "minutos")

      diff_seconds < 86_400 ->
        pluralize(div(diff_seconds, 3600), "hora", "horas")

      diff_seconds < 604_800 ->
        pluralize(div(diff_seconds, 86_400), "dia", "dias")

      true ->
        pluralize(div(diff_seconds, 604_800), "semana", "semanas")
    end
  end

  defp pluralize(1, singular, _plural), do: "1 #{singular}"
  defp pluralize(n, _singular, plural), do: "#{n} #{plural}"

  defp handle_add("", _sender) do
    {:reply, "[BOT] Por favor especifica o item a adicionar, ex: 'adiciona leite'."}
  end

  defp handle_add(item_name, sender) do
    changeset = ShoppingItem.changeset(%ShoppingItem{}, %{name: item_name, added_by: sender})

    case Repo.insert(changeset) do
      {:ok, item} ->
        {:reply, "[BOT] ✅ Adicionado: #{item.name}"}

      {:error, _changeset} ->
        {:reply, "[BOT] Não foi possível adicionar o item à lista de compras."}
    end
  end

  defp handle_remove("") do
    {:reply, "[BOT] Por favor especifica o item a remover, ex: 'remove leite'."}
  end

  defp handle_remove(search_term) do
    query =
      from(i in ShoppingItem,
        where: i.done == false and ilike(i.name, ^"%#{search_term}%"),
        order_by: [desc: i.inserted_at],
        limit: 1
      )

    case Repo.one(query) do
      nil ->
        {:reply, "[BOT] O item '#{search_term}' não foi encontrado na lista de compras."}

      item ->
        Repo.delete!(item)
        {:reply, "[BOT] 🗑️ Removido: #{item.name}"}
    end
  end

  defp handle_list do
    query =
      from(i in ShoppingItem,
        where: i.done == false,
        order_by: [asc: i.inserted_at]
      )

    items = Repo.all(query)

    if items == [] do
      {:reply, "[BOT] 🛒 A tua lista de compras está vazia."}
    else
      formatted =
        items
        |> Enum.with_index(1)
        |> Enum.map(fn {item, idx} -> "#{idx}. #{item.name}" end)
        |> Enum.join("\n")

      {:reply, "[BOT] 🛒 Lista de Compras:\n" <> formatted}
    end
  end

  defp handle_clear do
    from(i in ShoppingItem, where: i.done == false)
    |> Repo.delete_all()

    {:reply, "[BOT] 🧹 Lista de compras limpa."}
  end
end
