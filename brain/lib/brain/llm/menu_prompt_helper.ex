defmodule Brain.LLM.MenuPromptHelper do
  @moduledoc """
  Builds the system and user prompts for weekly dinner menu generation.

  Unlike the lightweight classification prompt in `Brain.LLM.PromptHelper`,
  this prompt receives heavy context (full pantry, meal history, learned
  preferences) and is only invoked when the classifier resolves to
  `generate_menu`.

  User-controlled data (pantry names, meal history, constraints) is kept in
  the user message, never in the system prompt, to defend against prompt
  injection.
  """

  @timezone "Europe/Lisbon"
  @max_constraints_length 500

  def build(pantry_items, history, preferences, constraints_raw, today) do
    {system_prompt(today, constraints_raw),
     user_prompt(pantry_items, history, preferences, constraints_raw)}
  end

  defp system_prompt(now, constraints_raw) do
    base =
      """
      You are the meal planner for a Portuguese family. You create weekly dinner menus.

      ## Current context
      - Today: #{format_datetime(now)}
      - Day of week: #{format_weekday(now)}
      - Timezone: #{@timezone}

      The menu must cover TOMORROW plus the next 6 days (7 meals total). Never include today.

      ## Menu rules
      - Portuguese cuisine focus: bacalhau, carne assada, sopas, arroz de pato, feijoada,
        açorda, polvo à lagareiro, etc. Propose variety across the week.
      - Creativity is welcome, but every dish must be recognizably Portuguese — no random fusion.
      - Do NOT repeat dishes already served in the recent history (see the user message).
      - Do not repeat the same main protein more than 2 times in the week.
      - Prefer dishes that use the pantry items listed in the user message; anything not already
        at home goes into `needs_to_buy`.
      - Always return the FULL recipe (ingredients + steps) for every day, even though it will
        not be shown immediately.

      ## Output format
      Respond with only this JSON, no prose, no markdown fences:
      {
        "menu": [
          {
            "day": "<weekday name, e.g. Terça-feira>",
            "date": "<ISO date YYYY-MM-DD>",
            "meal": "<dish name>",
            "prep_time_minutes": <integer>,
            "portions": <integer>,
            "notes": "",
            "needs_to_buy": ["<missing ingredient>", "..."],
            "recipe": {
              "ingredients": ["<ingredient with quantity>", "..."],
              "steps": ["<step 1>", "..."]
            }
          }
        ]
      }

      Exactly 7 entries in `menu`, one per day, starting tomorrow.
      """
      |> String.trim()

    constraints = String.trim(constraints_raw || "")

    if constraints == "" do
      base
    else
      """
      #{base}

      ## User-supplied hard rules (the following must be obeyed as strictly as the menu rules above)
      #{String.slice(constraints, 0, @max_constraints_length)}
      """
      |> String.trim()
    end
  end

  defp user_prompt(pantry_items, history, preferences, constraints_raw) do
    """
    Generate the weekly menu based on the context below.

    ## Pantry (currently at home)
    #{format_pantry(pantry_items)}

    ## Recent meals (last 4 weeks — do not repeat)
    #{format_history(history)}

    ## Preferences learned from feedback
    #{format_preferences(preferences)}

    ## User constraints for this week
    #{format_constraints(constraints_raw)}
    """
    |> String.trim()
  end

  defp format_pantry([]), do: "(empty)"
  defp format_pantry(items), do: items |> Enum.map(&"- #{&1.name}") |> Enum.join("\n")

  defp format_history([]), do: "(none)"
  defp format_history(meals), do: meals |> Enum.map(&"- #{&1}") |> Enum.join("\n")

  defp format_preferences(preferences) do
    likes = Map.get(preferences, :likes, [])
    dislikes = Map.get(preferences, :dislikes, [])

    like_lines = if likes == [], do: "(none)", else: Enum.map_join(likes, "\n", &"- #{&1}")

    dislike_lines =
      if dislikes == [], do: "(none)", else: Enum.map_join(dislikes, "\n", &"- #{&1}")

    "Liked:\n#{like_lines}\nDisliked:\n#{dislike_lines}"
  end

  defp format_constraints(""), do: "(none)"
  defp format_constraints(constraints), do: String.slice(constraints, 0, @max_constraints_length)

  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M (%A)")
  defp format_weekday(dt), do: Calendar.strftime(dt, "%A")
end
