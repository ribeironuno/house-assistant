defmodule Brain.Reminders do
  @moduledoc """
  Reminder context.

  Owns reminder command parsing, persistence, and Portuguese responses.
  """

  import Ecto.Query

  alias Brain.Repo
  alias Brain.Reminders.Reminder

  @lisbon_tz "Europe/Lisbon"

  @doc """
  Deletes every reminder scheduled for a group.
  """
  def clear(group_id) do
    from(r in Reminder, where: r.group_id == ^group_id)
    |> Repo.delete_all()

    {:reply, "[BOT] 🔔 Lembretes apagados."}
  end

  def schedule_from_text(_raw_text, _sender, nil) do
    {:reply, "[BOT] Não consigo guardar um lembrete sem saber em que grupo devo responder."}
  end

  def schedule_from_text(raw_text, sender, group_id) do
    raw_text
    |> extract_body()
    |> parse(DateTime.utc_now())
    |> case do
      {:ok, reminder_text, remind_at} ->
        create(reminder_text, remind_at, sender, group_id)

      {:error, :missing_text} ->
        {:reply,
         "[BOT] Por favor diz o que queres que eu lembre, ex: 'lembrar de pagar scouts daqui a 3 dias'."}

      {:error, :missing_time} ->
        {:reply, "[BOT] Por favor diz quando queres o lembrete, ex: 'logo' ou 'daqui a 3 dias'."}

      {:error, :duration_too_long} ->
        {:reply, "[BOT] 😕 Esse prazo é demasiado longo. O máximo são 10 anos."}

      {:error, :invalid_hour} ->
        {:reply, "[BOT] 😕 Essa hora não é válida. Usa um horário entre 0h e 23h."}
    end
  end

  defp extract_body(raw_text) do
    String.replace(
      raw_text,
      ~r/^\s*(lembrar(?:-me)?|lembra(?:-me)?|lembra(?:-nos)?)\s+de\s+/iu,
      "",
      global: false
    )
    |> String.trim()
  end

  @max_duration_seconds 3650 * 24 * 60 * 60

  defp parse("", _now), do: {:error, :missing_text}

  @weekday_map %{
    "segunda" => 1,
    "terça" => 2,
    "terca" => 2,
    "quarta" => 3,
    "quinta" => 4,
    "sexta" => 5,
    "sábado" => 6,
    "sabado" => 6,
    "domingo" => 0
  }

  @default_weekday_hour 10

  defp parse(body, now) do
    cond do
      match =
          Regex.run(
            ~r/\bdaqui\s+a\s+(\d+)\s+(minutos?|mins?|horas?|dias?|semanas?)\b/iu,
            body
          ) ->
        [phrase, amount_text, unit] = match
        reminder_text = remove_time_phrase(body, phrase)
        amount = String.to_integer(amount_text)
        seconds = duration_in_seconds(amount, unit)

        if seconds > @max_duration_seconds do
          {:error, :duration_too_long}
        else
          remind_at = DateTime.add(now, seconds, :second)
          validate_text(reminder_text, remind_at)
        end

      # "amanhã às 9h" / "amanhã às 18:00" / "amanhã às 18:30" — tomorrow at a specific time
      match = Regex.run(~r/\bamanh[ãa]\s+[àa]s\s+(\d{1,2})(?::(\d{2})|h)?\b/iu, body) ->
        phrase = Enum.at(match, 0)
        hour_str = Enum.at(match, 1)
        minute_str = Enum.at(match, 2)
        reminder_text = remove_time_phrase(body, phrase)
        hour = String.to_integer(hour_str)
        minute = if(minute_str, do: String.to_integer(minute_str), else: 0)

        with :ok <- validate_hour(hour) do
          remind_at = next_clock_time(now, hour, minute, days_ahead: 1)
          validate_text(reminder_text, remind_at)
        end

      # "à sexta" / "à segunda" / "à terça às 18h" / "à terça às 18:30" etc.
      match =
          Regex.run(
            ~r/\b[àa]\s+(segunda|terça|terca|quarta|quinta|sexta|sábado|sabado|domingo)(?:\s+[àa]s\s+(\d{1,2})(?::(\d{2})|h)?)?\b/iu,
            body
          ) ->
        weekday_name = Enum.at(match, 1)
        time_str = Enum.at(match, 2)
        minute_str = Enum.at(match, 3)
        phrase = Enum.at(match, 0)
        reminder_text = remove_time_phrase(body, phrase)
        weekday_num = @weekday_map[String.downcase(weekday_name)]
        hour = if time_str, do: String.to_integer(time_str), else: @default_weekday_hour
        minute = if(minute_str, do: String.to_integer(minute_str), else: 0)

        with :ok <- validate_hour(hour) do
          remind_at = next_weekday(now, weekday_num, hour, minute)
          validate_text(reminder_text, remind_at)
        end

      # "às 18h" / "às 18:00" / "às 18:30" / "às 9h" — today (or tomorrow if already past)
      match = Regex.run(~r/\b[àa]s\s+(\d{1,2})(?::(\d{2})|h)\b/iu, body) ->
        phrase = Enum.at(match, 0)
        hour_str = Enum.at(match, 1)
        minute_str = Enum.at(match, 2)
        reminder_text = remove_time_phrase(body, phrase)
        hour = String.to_integer(hour_str)
        minute = if(minute_str, do: String.to_integer(minute_str), else: 0)

        with :ok <- validate_hour(hour) do
          remind_at = next_clock_time(now, hour, minute, days_ahead: 0)
          validate_text(reminder_text, remind_at)
        end

      Regex.match?(~r/\blogo\b/iu, body) ->
        reminder_text = remove_time_phrase(body, ~r/\blogo\b/iu)
        remind_at = DateTime.add(now, 30 * 60, :second)
        validate_text(reminder_text, remind_at)

      Regex.match?(~r/\bamanh[ãa]\b/iu, body) ->
        reminder_text = remove_time_phrase(body, ~r/\bamanh[ãa]\b/iu)
        remind_at = DateTime.add(now, 24 * 60 * 60, :second)
        validate_text(reminder_text, remind_at)

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

  defp validate_hour(hour) when hour in 0..23, do: :ok
  defp validate_hour(_hour), do: {:error, :invalid_hour}

  @doc false
  defp next_weekday(now, target_day, hour, minute) do
    now_lisbon = DateTime.shift_zone!(now, @lisbon_tz)
    current_dow = Date.day_of_week(now_lisbon)

    days_ahead =
      if target_day > current_dow,
        do: target_day - current_dow,
        else: 7 - (current_dow - target_day)

    next_date = Date.add(DateTime.to_date(now_lisbon), days_ahead)

    DateTime.new!(next_date, Time.new!(hour, minute, 0), @lisbon_tz)
    |> DateTime.shift_zone!("Etc/UTC")
  end

  @doc false
  defp next_clock_time(now, hour, minute, opts) do
    days_ahead = opts[:days_ahead] || 0
    now_lisbon = DateTime.shift_zone!(now, @lisbon_tz)
    now_hour = now_lisbon.hour
    target_date = DateTime.to_date(now_lisbon) |> Date.add(days_ahead)

    target_date =
      if days_ahead == 0 and now_hour >= hour do
        Date.add(target_date, 1)
      else
        target_date
      end

    DateTime.new!(target_date, Time.new!(hour, minute, 0), @lisbon_tz)
    |> DateTime.shift_zone!("Etc/UTC")
  end

  defp remove_time_phrase(body, phrase) when is_binary(phrase) do
    body
    |> String.replace(phrase, "", global: false)
    |> clean_text()
  end

  defp remove_time_phrase(body, %Regex{} = regex) do
    body
    |> String.replace(regex, "", global: false)
    |> clean_text()
  end

  defp clean_text(text) do
    text
    |> String.trim()
    |> String.trim_trailing(".")
    |> String.trim_trailing(",")
    |> String.trim()
  end

  defp validate_text("", _remind_at), do: {:error, :missing_text}

  defp validate_text(reminder_text, remind_at),
    do: {:ok, reminder_text, DateTime.truncate(remind_at, :second)}

  defp create(reminder_text, remind_at, sender, group_id) do
    changeset =
      Reminder.changeset(%Reminder{}, %{
        text: reminder_text,
        group_id: group_id,
        created_by: sender,
        remind_at: remind_at
      })

    case Repo.insert(changeset) do
      {:ok, reminder} ->
        {:reply, format_confirmation(reminder)}

      {:error, _changeset} ->
        {:reply, "[BOT] Não foi possível guardar o lembrete."}
    end
  end

  defp format_confirmation(reminder) do
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
end
