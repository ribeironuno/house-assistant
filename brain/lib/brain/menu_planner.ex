defmodule Brain.MenuPlanner do
  @moduledoc """
  Weekly dinner menu planner.

  Generates a 7-day menu (tomorrow + 6 days) via the LLM, persists it in
  `weekly_menus` with the full recipes, and formats the summary/reply replies.

  The heavy prompt (pantry, history, preferences) lives in
  `Brain.LLM.MenuPromptHelper` and is only invoked when the classifier resolves
  to `generate_menu`.
  """

  require Logger

  alias Brain.MealFeedback
  alias Brain.MenuHistory
  alias Brain.Menu.WeeklyMenu
  alias Brain.LLM.MenuPromptHelper
  alias Brain.Pantry
  alias Brain.Repo

  @timezone "Europe/Lisbon"

  @schema %{
    type: "object",
    properties: %{
      menu: %{
        type: "array",
        items: %{
          type: "object",
          properties: %{
            day: %{type: "string"},
            date: %{type: "string"},
            meal: %{type: "string"},
            prep_time_minutes: %{type: "number"},
            portions: %{type: "number"},
            notes: %{type: "string"},
            needs_to_buy: %{type: "array", items: %{type: "string"}},
            recipe: %{
              type: "object",
              properties: %{
                ingredients: %{type: "array", items: %{type: "string"}},
                steps: %{type: "array", items: %{type: "string"}}
              },
              required: ["ingredients", "steps"]
            }
          },
          required: [
            "day",
            "date",
            "meal",
            "prep_time_minutes",
            "portions",
            "notes",
            "needs_to_buy",
            "recipe"
          ]
        }
      }
    },
    required: ["menu"]
  }

  def generate(constraints_raw, group_id) when is_binary(constraints_raw) do
    if enabled?() do
      pantry_items = Pantry.get_all()
      history = MenuHistory.recent_meals(group_id, weeks: 4)
      preferences = MealFeedback.summarize(group_id)
      today = DateTime.now!(@timezone)

      prompt = MenuPromptHelper.build(pantry_items, history, preferences, constraints_raw, today)
      user_prompt = "Gera o menu da semana respeitando as restrições dadas."

      case provider().generate_menu(prompt, user_prompt, @schema) do
        {:ok, %{"menu" => meals}} when is_list(meals) ->
          persist_and_reply(meals, group_id, constraints_raw)

        {:ok, _other} ->
          {:reply, "[BOT] 😕 Não consegui gerar o menu. Tenta novamente."}

        {:error, reason} ->
          log_error(reason)
          {:reply, "[BOT] 😕 Não consegui contactar o gerador de menus. Tenta novamente."}
      end
    else
      {:reply, "[BOT] ⚙️ A geração de menus está desativada."}
    end
  rescue
    exception ->
      Logger.error("[Brain] MenuPlanner failed: #{Exception.message(exception)}")
      {:reply, "[BOT] 😕 Ocorreu um erro ao gerar o menu. Tenta novamente."}
  end

  def get_recipe(search_term, group_id) when is_binary(search_term) do
    case MenuHistory.get_recipe_for_day(group_id, search_term) do
      nil ->
        {:reply, "[BOT] 😕 Não encontrei essa receita no menu desta semana."}

      meal ->
        {:reply, format_recipe(meal)}
    end
  end

  defp persist_and_reply(meals, group_id, constraints_raw) do
    attrs = %{
      group_id: group_id,
      constraints_raw: constraints_raw,
      meals: %{"menu" => meals},
      generated_at: DateTime.utc_now()
    }

    changeset = WeeklyMenu.changeset(%WeeklyMenu{}, attrs)

    case Repo.insert(changeset) do
      {:ok, _menu} ->
        {:reply, format_summary(meals)}

      {:error, changeset} ->
        Logger.error("[Brain] MenuPlanner persist failed: #{inspect(changeset.errors)}")
        {:reply, "[BOT] 😕 Não consegui guardar o menu. Tenta novamente."}
    end
  end

  defp format_summary(meals) do
    header = "[BOT] 🍽️ Menu da Semana"
    days = Enum.map_join(meals, "\n", &format_day_line/1)

    shopping =
      meals
      |> Enum.flat_map(&Map.get(&1, "needs_to_buy", []))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    shopping_line =
      if shopping == [], do: "", else: "\n\n🛒 Para comprar: " <> Enum.join(shopping, ", ")

    """
    #{header}
    #{days}#{shopping_line}

    Diz "receita de terça" para veres o passo a passo. 👍/👎 um prato para eu ir aprendendo os teus gostos.
    """
    |> String.trim()
  end

  defp format_day_line(meal) do
    day = Map.get(meal, "day", "")
    date = format_date(Map.get(meal, "date", ""))
    dish = Map.get(meal, "meal", "")
    prep = Map.get(meal, "prep_time_minutes", 0)
    portions = Map.get(meal, "portions", 0)

    needs =
      case Map.get(meal, "needs_to_buy", []) do
        [] -> ""
        items -> "\n🛒 Precisa comprar: " <> Enum.join(items, ", ")
      end

    "#{day} (#{date}) — #{dish}\n⏱ #{prep} min | 👥 #{portions} doses#{needs}"
  end

  defp format_date(""), do: ""

  defp format_date(iso_date),
    do: String.slice(iso_date, 8..9) <> "/" <> String.slice(iso_date, 5..6)

  defp format_recipe(meal) do
    day = Map.get(meal, "day", "")
    dish = Map.get(meal, "meal", "")
    recipe = Map.get(meal, "recipe", %{})

    ingredients =
      recipe
      |> Map.get("ingredients", [])
      |> Enum.map_join("\n", &"- #{&1}")

    steps =
      recipe
      |> Map.get("steps", [])
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {step, idx} -> "#{idx}. #{step}" end)

    """
    [BOT] 📖 Receita: #{dish} (#{day})
    Ingredientes:
    #{ingredients}
    Modo de preparo:
    #{steps}
    """
    |> String.trim()
  end

  defp enabled?, do: Application.get_env(:brain, :menu_planner_enabled, true)
  defp provider, do: Application.get_env(:brain, :llm_provider, Brain.LLM.Providers.Gemini)

  defp log_error(reason) do
    Logger.error("[Brain] MenuPlanner LLM call failed: #{inspect(reason)}")
  end
end
