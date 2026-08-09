defmodule Brain.CommandsPantryMenuIntegrationTest do
  use BrainWeb.ConnCase, async: false

  alias Brain.Commands
  alias Brain.Menu.WeeklyMenu
  alias Brain.Menu.MealFeedback
  alias Brain.Pantry.Item
  alias Brain.Repo

  @group_id "group_1"

  defmodule RoutingProvider do
    @behaviour Brain.LLM.Provider

    def set_classifier_reply(reply), do: Process.put(:classifier_reply, reply)

    def generate_structured(system_prompt, _user, _schema) do
      if menu_prompt?(system_prompt) do
        menu_reply()
      else
        Process.get(:classifier_reply) || {:error, :no_reply_set}
      end
    end

    def generate_menu(system_prompt, _user, _schema) do
      menu_reply()
    end

    def generate_structured_with_media(_system, _user, _schema, _media),
      do: {:error, :no_media}

    defp menu_prompt?(system_prompt),
      do: String.contains?(system_prompt, "meal planner")

    defp menu_reply do
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

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Application.put_env(:brain, :llm_command_interpreter_enabled, true)
    Application.put_env(:brain, :llm_provider, RoutingProvider)
    Application.put_env(:brain, :menu_planner_enabled, true)

    on_exit(fn ->
      Application.delete_env(:brain, :llm_command_interpreter_enabled)
      Application.put_env(:brain, :llm_provider, Brain.LLM.Providers.TestStub)
      Application.delete_env(:brain, :menu_planner_enabled)
    end)
  end

  defp classify(reply) do
    RoutingProvider.set_classifier_reply({:ok, reply})
  end

  test "tenho command adds items to pantry end-to-end" do
    classify(%{
      "action" => "add_pantry_items",
      "items" => ["arroz", "frango"],
      "confidence" => 0.9
    })

    assert {:reply, reply} = Commands.handle("tenho arroz, frango", "user_1", @group_id)
    assert reply =~ "[BOT] ✅ Adicionados à despensa:"

    items = Repo.all(Item)
    assert length(items) == 2
  end

  test "despensa command lists pantry end-to-end" do
    Brain.Pantry.add_many(["arroz", "frango"], @group_id, "user_1")

    classify(%{"action" => "list_pantry", "confidence" => 0.9})

    assert {:reply, reply} = Commands.handle("o que tenho na despensa?", "user_1", @group_id)
    assert reply =~ "[BOT] 🏠 Despensa:"
    assert reply =~ "arroz"
    assert reply =~ "frango"
  end

  test "generate menu command goes through the menu provider end-to-end" do
    classify(%{
      "action" => "generate_menu",
      "constraints" => "quarta rápido",
      "confidence" => 0.9
    })

    assert {:reply, reply} =
             Commands.handle("faz-me o menu da semana quarta rápido", "user_1", "group_1")

    assert reply =~ "[BOT] 🍽️ Menu da Semana"
    assert reply =~ "Frango assado com batatas"
    assert reply =~ "🛒 Para comprar: frango, natas, bacalhau"

    [menu] = Repo.all(WeeklyMenu)
    assert menu.group_id == "group_1"
    assert menu.constraints_raw == "quarta rápido"
  end

  test "receita command fetches recipe end-to-end" do
    classify(%{
      "action" => "generate_menu",
      "constraints" => "",
      "confidence" => 0.9
    })

    Commands.handle("faz-me o menu", "user_1", "group_1")

    classify(%{"action" => "get_recipe", "item" => "terça", "confidence" => 0.9})

    assert {:reply, reply} = Commands.handle("receita de terça", "user_1", "group_1")
    assert reply =~ "[BOT] 📖 Receita: Bacalhau com natas (Terça-feira)"
    assert reply =~ "- 4 postas de bacalhau"
    assert reply =~ "1. Cozer"
  end

  test "rate_meal command persists feedback end-to-end" do
    classify(%{
      "action" => "rate_meal",
      "item" => "Bacalhau",
      "sentiment" => "like",
      "confidence" => 0.9
    })

    assert {:reply, reply} = Commands.handle("gostei do bacalhau", "user_1", "group_1")
    assert reply =~ "[BOT] 📝 Registado: gostei de Bacalhau."

    [feedback] = Repo.all(MealFeedback)
    assert feedback.group_id == "group_1"
    assert feedback.meal_name == "Bacalhau"
    assert feedback.sentiment == "like"
    assert feedback.raw_text == "gostei do bacalhau"
  end
end
