defmodule Brain.LLM.CommandInterpreterTest do
  use ExUnit.Case, async: false

  alias Brain.LLM.CommandInterpreter

  defmodule MockProvider do
    @behaviour Brain.LLM.Provider

    def set_reply(reply), do: Process.put(:reply, reply)

    def generate_structured(_system, _user, _schema) do
      Process.get(:reply) || {:error, :no_reply_set}
    end

    def generate_menu(_system, _user, _schema) do
      Process.get(:reply) || {:error, :no_reply_set}
    end

    def generate_structured_with_media(_system, _user, _schema, _media), do: {:error, :no_media}
  end

  setup do
    Application.put_env(:brain, :llm_command_interpreter_enabled, true)
    Application.put_env(:brain, :llm_provider, MockProvider)

    on_exit(fn ->
      Application.delete_env(:brain, :llm_command_interpreter_enabled)
      Application.put_env(:brain, :llm_provider, Brain.LLM.Providers.TestStub)
    end)
  end

  defp reply(interpretation) do
    MockProvider.set_reply({:ok, interpretation})
  end

  test "add_pantry_items maps multiple items to pantry action" do
    reply(%{
      "action" => "add_pantry_items",
      "items" => ["arroz", "frango", "atum"],
      "confidence" => 0.9
    })

    assert {:ok, {:add_pantry_items, ["arroz", "frango", "atum"]}} =
             CommandInterpreter.interpret("tenho arroz, frango, atum")
  end

  test "remove_pantry_item maps to pantry action" do
    reply(%{"action" => "remove_pantry_item", "item" => "arroz", "confidence" => 0.9})

    assert {:ok, {:remove_pantry_item, "arroz"}} =
             CommandInterpreter.interpret("usei arroz")
  end

  test "list_pantry maps to pantry action" do
    reply(%{"action" => "list_pantry", "confidence" => 0.9})

    assert {:ok, :list_pantry} = CommandInterpreter.interpret("o que tenho na despensa?")
  end

  test "clear_pantry maps to pantry action" do
    reply(%{"action" => "clear_pantry", "confidence" => 0.9})

    assert {:ok, :clear_pantry} = CommandInterpreter.interpret("limpa a despensa")
  end

  test "generate_menu passes constraints verbatim" do
    reply(%{
      "action" => "generate_menu",
      "constraints" => "quarta rápido, 4 doses",
      "confidence" => 0.9
    })

    assert {:ok, {:generate_menu, "quarta rápido, 4 doses"}} =
             CommandInterpreter.interpret("faz-me o menu da semana, quarta rápido")
  end

  test "generate_menu without constraints returns empty string" do
    reply(%{"action" => "generate_menu", "confidence" => 0.9})

    assert {:ok, {:generate_menu, ""}} =
             CommandInterpreter.interpret("faz-me o menu da semana")
  end

  test "get_recipe maps to action with the requested day" do
    reply(%{"action" => "get_recipe", "item" => "terça", "confidence" => 0.9})

    assert {:ok, {:get_recipe, "terça"}} =
             CommandInterpreter.interpret("receita de terça")
  end

  test "rate_meal maps like sentiment" do
    reply(%{
      "action" => "rate_meal",
      "item" => "Bacalhau à Brás",
      "sentiment" => "like",
      "confidence" => 0.9
    })

    assert {:ok, {:rate_meal, "Bacalhau à Brás", "like"}} =
             CommandInterpreter.interpret("gostei do bacalhau à brás")
  end

  test "rate_meal maps dislike sentiment" do
    reply(%{
      "action" => "rate_meal",
      "item" => "Feijoada",
      "sentiment" => "dislike",
      "confidence" => 0.9
    })

    assert {:ok, {:rate_meal, "Feijoada", "dislike"}} =
             CommandInterpreter.interpret("não gostei da feijoada")
  end

  test "existing shopping actions still work" do
    reply(%{
      "action" => "add_items",
      "items" => ["leite"],
      "confidence" => 0.9
    })

    assert {:ok, "adiciona leite"} = CommandInterpreter.interpret("adiciona leite")
  end

  test "low confidence is ignored" do
    reply(%{"action" => "list_pantry", "confidence" => 0.3})

    assert :ignore = CommandInterpreter.interpret("oi")
  end
end
