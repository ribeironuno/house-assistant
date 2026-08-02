defmodule Brain.MenuPlannerTest do
  use BrainWeb.ConnCase, async: false

  alias Brain.Menu.WeeklyMenu
  alias Brain.MenuPlanner
  alias Brain.Repo

  defmodule MockProvider do
    @behaviour Brain.LLM.Provider

    def generate_structured(_system, _user, _schema), do: mock_reply()
    def generate_menu(_system, _user, _schema), do: mock_reply()
    def generate_structured_with_media(_system, _user, _schema, _media), do: mock_reply()

    defp mock_reply do
      {:ok,
       %{
         "menu" => [
           %{
             "day" => "Segunda-feira",
             "date" => "2026-08-03",
             "meal" => "Frango assado com batatas",
             "prep_time_minutes" => 45,
             "portions" => 4,
             "notes" => "",
             "needs_to_buy" => ["frango"],
             "recipe" => %{
               "ingredients" => ["1 frango", "4 batatas"],
               "steps" => ["Assar", "Servir"]
             }
           },
           %{
             "day" => "Terça-feira",
             "date" => "2026-08-04",
             "meal" => "Bacalhau com natas",
             "prep_time_minutes" => 60,
             "portions" => 4,
             "notes" => "",
             "needs_to_buy" => ["natas", "bacalhau"],
             "recipe" => %{
               "ingredients" => ["4 postas de bacalhau", "1L natas"],
               "steps" => ["Cozer", "Gratinar"]
             }
           }
         ]
       }}
    end
  end

  defmodule FailingProvider do
    @behaviour Brain.LLM.Provider

    def generate_structured(_system, _user, _schema), do: {:error, :provider_down}
    def generate_menu(_system, _user, _schema), do: {:error, :provider_down}

    def generate_structured_with_media(_system, _user, _schema, _media),
      do: {:error, :provider_down}
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Application.put_env(:brain, :llm_provider, MockProvider)
    Application.put_env(:brain, :menu_planner_enabled, true)

    on_exit(fn ->
      Application.delete_env(:brain, :llm_provider)
      Application.delete_env(:brain, :menu_planner_enabled)
    end)
  end

  test "generate persists a weekly menu and returns a formatted summary" do
    assert {:reply, reply} = MenuPlanner.generate("", "group_1")

    assert reply =~ "[BOT] 🍽️ Menu da Semana"
    assert reply =~ "Frango assado com batatas"
    assert reply =~ "Bacalhau com natas"
    assert reply =~ "🛒 Para comprar: frango, natas, bacalhau"

    [menu] = Repo.all(WeeklyMenu)
    assert menu.group_id == "group_1"
    assert menu.constraints_raw in [nil, ""]
    assert %{"menu" => meals} = menu.meals
    assert length(meals) == 2
    assert hd(meals)["meal"] == "Frango assado com batatas"
  end

  test "generate persists constraints verbatim" do
    MenuPlanner.generate("quarta rápido, 4 doses", "group_1")

    [menu] = Repo.all(WeeklyMenu)
    assert menu.constraints_raw == "quarta rápido, 4 doses"
  end

  test "generate returns error reply when provider fails" do
    Application.put_env(:brain, :llm_provider, FailingProvider)

    assert {:reply, reply} = MenuPlanner.generate("", "group_1")
    assert reply =~ "Não consegui"
    assert Repo.all(WeeklyMenu) == []
  end

  test "get_recipe returns the stored recipe for a weekday" do
    MenuPlanner.generate("", "group_1")

    assert {:reply, reply} = MenuPlanner.get_recipe("terça", "group_1")
    assert reply =~ "[BOT] 📖 Receita: Bacalhau com natas"
    assert reply =~ "Ingredientes:"
    assert reply =~ "- 4 postas de bacalhau"
    assert reply =~ "- 1L natas"
    assert reply =~ "Modo de preparo:"
    assert reply =~ "1. Cozer"
    assert reply =~ "2. Gratinar"
  end

  test "get_recipe returns error when recipe is not found" do
    MenuPlanner.generate("", "group_1")

    assert {:reply, reply} = MenuPlanner.get_recipe("quinta", "group_1")
    assert reply =~ "Não encontrei"
  end

  test "get_recipe returns error when no menu exists" do
    assert {:reply, reply} = MenuPlanner.get_recipe("terça", "group_1")
    assert reply =~ "Não encontrei"
  end
end
