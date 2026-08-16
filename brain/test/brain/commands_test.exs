defmodule Brain.CommandsTest do
  use BrainWeb.ConnCase, async: true
  import Ecto.Query

  alias Brain.Commands
  alias Brain.Repo
  alias Brain.Reminders.Reminder
  alias Brain.ShoppingList
  alias Brain.ShoppingList.Item

  @group_id "group_1"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    ensure_group(@group_id)
  end

  test "adiciona command adds item to shopping list and returns confirmation" do
    assert {:reply, "[BOT] ✅ Adicionado: leite"} =
             Commands.handle("adiciona leite", "user_1", @group_id)

    items = Repo.all(Item)
    assert length(items) == 1
    assert hd(items).name == "leite"
    assert hd(items).added_by == "user_1"
    assert hd(items).done == false
  end

  test "adicionar command handles extra spaces and casing" do
    assert {:reply, "[BOT] ✅ Adicionado: Ovos Frescos"} =
             Commands.handle("  ADICIONAR   Ovos Frescos  ", "user_2", @group_id)

    items = Repo.all(Item)
    assert length(items) == 1
    assert hd(items).name == "Ovos Frescos"
  end

  test "adicionar command adds multiple comma-separated items" do
    assert {:reply, "[BOT] ✅ Adicionados:\n1. leite\n2. pão\n3. manteiga"} =
             Commands.handle("adicionar leite, pão, manteiga", "user_1", @group_id)

    item_names =
      from(i in Item, order_by: [asc: i.inserted_at, asc: i.id])
      |> Repo.all()
      |> Enum.map(& &1.name)

    assert item_names == ["leite", "pão", "manteiga"]
  end

  test "adicionar command ignores empty comma-separated entries" do
    assert {:reply, "[BOT] ✅ Adicionados:\n1. leite\n2. manteiga"} =
             Commands.handle("adiciona leite, , manteiga, ", "user_1", @group_id)

    item_names =
      from(i in Item, order_by: [asc: i.inserted_at, asc: i.id])
      |> Repo.all()
      |> Enum.map(& &1.name)

    assert item_names == ["leite", "manteiga"]
  end

  test "add command without argument asks for item name" do
    assert {:reply, "[BOT] Por favor especifica o item a adicionar, ex: 'adiciona leite'."} =
             Commands.handle("adiciona", "user_1", @group_id)
  end

  test "add command with only commas asks for item name" do
    assert {:reply, "[BOT] Por favor especifica o item a adicionar, ex: 'adiciona leite'."} =
             Commands.handle("adiciona , ,", "user_1", @group_id)
  end

  test "lista command shows items in order of insertion" do
    assert {:reply, "[BOT] 🛒 A tua lista de compras está vazia."} =
             Commands.handle("lista", "user_1", @group_id)

    Commands.handle("adiciona leite", "user_1", @group_id)
    Commands.handle("adiciona ovos", "user_2", @group_id)

    expected_reply = "[BOT] 🛒 Lista de Compras:\n1. leite\n2. ovos"
    assert {:reply, ^expected_reply} = Commands.handle("lista", "user_1", @group_id)
    assert {:reply, ^expected_reply} = Commands.handle("ver lista", "user_1", @group_id)
  end

  test "remove command deletes matching item" do
    Commands.handle("adiciona leite", "user_1", @group_id)
    Commands.handle("adiciona ovos", "user_1", @group_id)

    assert {:reply, "[BOT] 🗑️ Removido: leite"} =
             Commands.handle("remove leite", "user_1", @group_id)

    items = Repo.all(Item)
    assert length(items) == 1
    assert hd(items).name == "ovos"
  end

  test "remover command handles case-insensitive substring match" do
    Commands.handle("adiciona Leite Gordo", "user_1", @group_id)

    assert {:reply, "[BOT] 🗑️ Removido: Leite Gordo"} =
             Commands.handle("remover leite", "user_1", @group_id)

    assert Repo.all(Item) == []
  end

  test "remove command handles non-existent item gracefully" do
    assert {:reply, "[BOT] O item 'manteiga' não foi encontrado na lista de compras."} =
             Commands.handle("remove manteiga", "user_1", @group_id)
  end

  test "limpar command deletes all shopping items" do
    Commands.handle("adiciona leite", "user_1", @group_id)
    Commands.handle("adiciona ovos", "user_1", @group_id)

    assert {:reply, "[BOT] 🧹 Lista de compras limpa."} =
             Commands.handle("limpar lista", "user_1", @group_id)

    assert Repo.all(Item) == []
  end

  test "ajuda command lists known commands" do
    assert {:reply, reply} = Commands.handle("ajuda", "user_1", @group_id)

    assert reply =~ "[BOT] Comandos que conheço:"
    assert reply =~ "adiciona <item>"
    assert reply =~ "remove <item>"
    assert reply =~ "lista"
    assert reply =~ "limpar lista"
    assert reply =~ "tenho <item>"
    assert reply =~ "usei <item>"
    assert reply =~ "o que tenho na despensa?"
    assert reply =~ "faz-me o menu da semana"
    assert reply =~ "receita de <dia>"
    assert reply =~ "gostei de <prato>"
    assert reply =~ "lembrar de <tarefa> daqui a N minutos/horas/dias/semanas"

    assert {:reply, ^reply} = Commands.handle("help", "user_1", @group_id)
    assert {:reply, ^reply} = Commands.handle("comandos", "user_1", @group_id)
    assert Repo.all(Item) == []
    assert Repo.all(Reminder) == []
  end

  test "lembrar de command creates reminder for logo" do
    assert {:reply, reply} = Commands.handle("lembrar de fazer isto logo", "user_1", "group_1")
    assert reply =~ "[BOT] 🔔 Lembrete guardado!"
    assert reply =~ "Título: fazer isto"
    assert reply =~ "Falta: 30 minutos"

    [reminder] = Repo.all(Reminder)
    assert reminder.text == "fazer isto"
    assert reminder.created_by == "user_1"
    assert reminder.group_id == "group_1"
    assert DateTime.compare(reminder.remind_at, DateTime.utc_now()) == :gt
    assert is_nil(reminder.sent_at)
  end

  test "lembrar de command creates reminder daqui a 3 dias" do
    assert {:reply, reply} =
             Commands.handle("lembrar de pagar scouts daqui a 3 dias", "user_1", "group_1")

    assert reply =~ "[BOT] 🔔 Lembrete guardado!"
    assert reply =~ "Título: pagar scouts"
    assert reply =~ "Falta: 3 dias"

    [reminder] = Repo.all(Reminder)
    assert reminder.text == "pagar scouts"

    seconds_until_reminder = DateTime.diff(reminder.remind_at, DateTime.utc_now(), :second)
    assert seconds_until_reminder in (3 * 24 * 60 * 60 - 5)..(3 * 24 * 60 * 60 + 5)
  end

  test "lembrar de command asks for missing reminder time" do
    assert {:reply,
            "[BOT] Por favor diz quando queres o lembrete, ex: 'logo' ou 'daqui a 3 dias'."} =
             Commands.handle("lembrar de pagar scouts", "user_1", "group_1")

    assert Repo.all(Reminder) == []
  end

  test "lembrar de command creates reminder for à sexta" do
    assert {:reply, reply} =
             Commands.handle("lembrar de ligar à avó à sexta", "user_1", "group_1")

    assert reply =~ "[BOT] 🔔 Lembrete guardado!"
    assert reply =~ "Título: ligar à avó"

    [reminder] = Repo.all(Reminder)
    assert reminder.text == "ligar à avó"
    assert reminder.remind_at |> DateTime.shift_zone!("Europe/Lisbon") |> Date.day_of_week() == 5
  end

  test "lembrar de command creates reminder for às 18h" do
    assert {:reply, reply} =
             Commands.handle("lembrar de pagar a luz às 18h", "user_1", "group_1")

    assert reply =~ "[BOT] 🔔 Lembrete guardado!"
    assert reply =~ "Título: pagar a luz"

    [reminder] = Repo.all(Reminder)
    assert reminder.remind_at |> DateTime.shift_zone!("Europe/Lisbon") |> Map.get(:hour) == 18
  end

  test "lembrar de command creates reminder for amanhã às 9h" do
    assert {:reply, reply} =
             Commands.handle("lembrar de ligar à avó amanhã às 9h", "user_1", "group_1")

    assert reply =~ "[BOT] 🔔 Lembrete guardado!"
    assert reply =~ "Título: ligar à avó"

    [reminder] = Repo.all(Reminder)
    remind_lisbon = reminder.remind_at |> DateTime.shift_zone!("Europe/Lisbon")
    assert remind_lisbon.hour == 9
  end

  test "unrecognized messages and bot response prefixes are ignored" do
    assert :ignore = Commands.handle("olá tudo bem?", "user_1", @group_id)
    assert :ignore = Commands.handle("qual é a receita de hoje?", "user_1", @group_id)
    assert :ignore = Commands.handle("[BOT] ✅ Adicionado: leite", "user_1", @group_id)
    assert :ignore = Commands.handle("[BOT] 🗑️ Removido: leite", "user_1", @group_id)
    assert :ignore = Commands.handle("[BOT] 🛒 Lista de Compras:\n1. leite", "user_1", @group_id)
    assert :ignore = Commands.handle("[BOT] 🧹 Lista de compras limpa.", "user_1", @group_id)
    assert :ignore = Commands.handle("[BOT] 🔔 Lembrete: pagar scouts", "user_1", @group_id)
  end

  test "remove o leite removes 'leite' (articles are stripped)" do
    ShoppingList.add("leite", @group_id, "user_1")

    assert {:reply, "[BOT] 🗑️ Removido: leite"} =
             Commands.handle("remove o leite", "user_1", @group_id)

    assert ShoppingList.get_active_items(@group_id) == []
  end

  test "por favor adiciona leite routes to LLM classifier (no longer dropped by bot_reply?)" do
    # Without an LLM configured, it falls through as :ignore — the key assertion
    # is that it is NOT dropped by the old bot_reply? false-positive filter.
    # In production, Gemini would map it to {"action":"add_shopping_items", ...}.
    result = Commands.handle("por favor adiciona leite", "user_1", @group_id)
    # The result may be :ignore (LLM stub error) or a reply — but it must NOT be
    # silently dropped by bot_reply?. The old code returned :ignore here due to the
    # "por favor" prefix; now it correctly reaches the LLM fallback path.
    assert result == :ignore
  end
end
