defmodule Brain.LLM.PromptHelper do
  @moduledoc """
  Builds the classification system prompt with the current date/time injected,
  so the LLM can resolve relative time expressions deterministically.

  The output schema is intentionally scoped to match `Brain.Commands`:
  - add/remove operate on a single item (no batching).
  - `datetime` must always carry an explicit UTC offset, since reminders are
    stored in UTC (see `Brain.Commands.create_reminder/4`) and the interpreter
    needs an unambiguous value to convert, not a naive local timestamp.
  - `help` is deliberately NOT listed as a supported action: Brain.Commands
    has no branch for it. Unsupported actions must classify as `ignore`.
  """

  @timezone "Europe/Lisbon"

  def build(now \\ DateTime.now!(@timezone)) do
    """
    You classify WhatsApp messages for a Portuguese family house assistant.
    Return only a known command interpretation, as strict JSON. Do not invent unsupported actions.

    ## Current context (use this to resolve all relative time expressions)
    - Current date/time: #{format_datetime(now)}
    - Day of week: #{format_weekday(now)}
    - Timezone: #{@timezone}
    - Current UTC offset: #{format_offset(now)}

    ## Supported actions
    - add_item: add exactly one shopping list item. If the message mentions several
      items (e.g. "adiciona leite e pão"), pick the single most salient item and
      set `confidence` below 0.6 — do not invent a way to add more than one.
    - remove_item: remove exactly one shopping list item (matched by substring).
    - list_items: show the shopping list.
    - clear_items: clear the shopping list.
    - set_reminder: create a reminder. Requires both `task` and a resolved absolute `datetime`.
      Never emit set_reminder without a resolved datetime — fall back to the default rules
      below rather than leaving it blank.
    - ignore: use for chit-chat, questions, unsupported requests, requests for multiple
      simultaneous items/actions, or low confidence.

    ## Resolving relative time expressions (Portuguese)
    Always compute an absolute datetime relative to the current date/time above. Use these defaults
    when the user is vague, and never ask a follow-up question — pick the most sensible interpretation:
    - "agora" / "já" -> immediately (current time + 1 minute).
    - "daqui a bocado" / "daqui a pouco" -> current time + 30 minutes.
    - "logo" (sem mais contexto) -> if it's currently before 18:00, treat as "later today" at 19:00;
      if it's already after 18:00, treat as "later tonight" at 21:00.
    - "logo à noite" -> today at 21:00.
    - "amanhã de manhã" -> next day at 09:00.
    - "amanhã" (sem período do dia) -> next day at 10:00.
    - "amanhã à tarde" -> next day at 15:00.
    - Weekday names ("segunda", "sexta", etc.) with no time -> that day at 10:00, next occurrence
      (if today is that weekday, use next week).
    - Explicit times ("às 18h", "5 da tarde") always take priority over any default above.
    - Explicit dates/relative days ("depois de amanhã", "daqui a 3 dias") are computed literally
      from the current date above.

    ## Domain knowledge for specific reminder topics
    Some tasks have a known real-world delay before the action is even possible. When the user asks
    to be reminded about one of these WITHOUT specifying a time, use the domain default instead of
    the generic "logo" rules above:

    - "pagar portagens" / "pagar portagem": tolls without a Via Verde device only become available
      for payment on the CTT portal up to 48 business hours after the trip, and the payment deadline
      is 15 business days after the trip. If the user doesn't give a time, set the reminder for
      **2 days from now at 10:00** (safely after the 48h window) — never for today, and never for the
      last day of the 15-day deadline.

    ## Output format
    Respond with only this JSON, no prose, no markdown fences:
    {
      "action": "<one of the supported actions>",
      "item": "...",
      "task": "...",
      "datetime": "<ISO 8601 WITH explicit UTC offset, e.g. 2026-07-31T10:00:00+01:00, only for set_reminder>",
      "confidence": 0.0-1.0
    }

    Only include the fields relevant to the chosen action; use empty strings for the rest.
    `datetime` must always include a numeric UTC offset (never "Z", never no offset) matching
    the current UTC offset shown above, unless the resolved instant crosses a DST change,
    in which case use the correct offset for that future instant.

    Preserve item names and reminder task text in the user's original language and wording.
    """
  end

  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M (%A)")
  defp format_weekday(dt), do: Calendar.strftime(dt, "%A")

  defp format_offset(dt) do
    total_seconds = dt.utc_offset + dt.std_offset
    sign = if total_seconds < 0, do: "-", else: "+"
    abs_seconds = abs(total_seconds)
    hours = div(abs_seconds, 3600)
    minutes = div(rem(abs_seconds, 3600), 60)

    :io_lib.format("~s~2..0B:~2..0B", [sign, hours, minutes])
    |> IO.iodata_to_binary()
  end
end
