defmodule Brain.MenuHistory do
  @moduledoc """
  Menu history context.

  Provides recent meals to avoid repetition in new menu generation.
  """

  import Ecto.Query

  alias Brain.Repo
  alias Brain.Menu.WeeklyMenu

  def recent_meals(group_id, opts \\ []) do
    weeks = Keyword.get(opts, :weeks, 4)
    since = DateTime.add(DateTime.utc_now(), -weeks * 7 * 24 * 60 * 60, :second)

    menus =
      from(m in WeeklyMenu,
        where: m.group_id == ^group_id and m.inserted_at >= ^since,
        order_by: [desc: m.inserted_at]
      )
      |> Repo.all()

    menus
    |> Enum.flat_map(fn menu ->
      case menu.meals do
        %{"menu" => meals} when is_list(meals) ->
          Enum.map(meals, &Map.get(&1, "meal"))

        _ ->
          []
      end
    end)
    |> Enum.uniq()
  end

  def get_latest(group_id) do
    from(m in WeeklyMenu,
      where: m.group_id == ^group_id,
      order_by: [desc: m.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  def get_recipe_for_day(group_id, day_name) do
    case get_latest(group_id) do
      nil ->
        nil

      menu ->
        case menu.meals do
          %{"menu" => meals} when is_list(meals) ->
            target = String.downcase(day_name)

            meal =
              Enum.find(meals, fn meal ->
                meal_day = Map.get(meal, "day", "") |> String.downcase()
                meal_name = Map.get(meal, "meal", "") |> String.downcase()

                String.starts_with?(meal_day, target) || String.contains?(meal_name, target)
              end)

            meal

          _ ->
            nil
        end
    end
  end
end
