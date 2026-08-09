defmodule Brain.Groups do
  require Logger

  @moduledoc """
  Multi-group (multi-tenant) activation context.

  A WhatsApp group must explicitly opt in before the bot processes commands
  there. The flow is:

  1. The bot is added to a group (bridge sends a `group_join` event) OR the
     first message arrives from an unknown group.
  2. The bot introduces itself (`intro_text/0`) and asks the group to reply
     "sim" or "não".
  3. On "sim" the group is activated and the bot answers with
     `activated_text/0`.
  4. On "não" the group is marked `left` and the bot asks the bridge to leave
     the group (`farewell_text/0`). The group can be added again later; a new
     `group_join` event will re-run the introduction.

  ## Return contract

  All `handle_message/3` / `handle_join/1` calls return one of:

    - `{:reply, text}`  — send `text` back to the group
    - `:proceed`        — group is active; run the normal command pipeline
    - `:ignore`         — do nothing (left/declined group, bot echoes, ...)
    - `{:leave, text}`  — send `text`, then tell the bridge to leave the group
  """

  alias Brain.Repo
  alias Brain.Groups.Group
  alias Brain.WhatsApp.BridgeClient

  @intro_text """
              [BOT] Olá! 👋 Eu sou um bot que ajuda com:
              🛒 Lista de compras
              🏠 Despensa
              🍽️ Menu da semana
              🔔 Lembretes

              Queres que fique ativo neste grupo? Responde "sim" ou "não".
              """
              |> String.trim_trailing()

  @activated_text """
                  [BOT] 🎉 Perfeito! Fui ativado neste grupo. Escreve "ajuda" para veres os comandos que conheço.
                  """
                  |> String.trim_trailing()

  @farewell_text """
                 [BOT] 👋 Ok, vou sair do grupo. Se mudares de ideias, adiciona-me novamente.
                 """
                 |> String.trim_trailing()

  @ask_again_text """
                  [BOT] Ainda não percebi. Queres que fique ativo neste grupo? Responde "sim" ou "não".
                  """
                  |> String.trim_trailing()

  @doc "The introduction message shown when the bot joins a group."
  def intro_text, do: @intro_text

  @doc "The confirmation message shown after a group replies 'sim'."
  def activated_text, do: @activated_text

  @doc "The farewell message shown before the bot leaves a group."
  def farewell_text, do: @farewell_text

  @doc "Prompt shown while a group is pending and sends something that is not sim/não."
  def ask_again_text, do: @ask_again_text

  @doc """
  Handles a `group_join` event (bot added to a group).

  Returns `{:reply, intro_text}` unless the group is already active.
  """
  def handle_join(group_id) do
    case get_group(group_id) do
      %Group{status: "active"} ->
        :ignore

      _ ->
        register_pending(group_id)
        {:reply, intro_text()}
    end
  end

  @doc """
  Gates an incoming message by the group's activation status.

  See the module doc for the return contract.
  """
  def handle_message(group_id, text, _sender) do
    case get_group(group_id) do
      nil ->
        register_pending(group_id)
        {:reply, intro_text()}

      %Group{status: "pending"} ->
        handle_pending(group_id, text)

      %Group{status: "active"} ->
        :proceed

      %Group{status: "left"} ->
        :ignore
    end
  end

  defp handle_pending(group_id, text) do
    normalized = normalize(text)

    cond do
      positive_answer?(normalized) ->
        activate(group_id)
        {:reply, activated_text()}

      negative_answer?(normalized) ->
        mark_left(group_id)
        {:leave, farewell_text()}

      true ->
        {:reply, ask_again_text()}
    end
  end

  @positive ~w(sim s y yes quero ok okay claro)
  @positive_prefixes ["sim,", "s,", "sim!", "quero sim", "pode ser", "sim quero"]
  @negative ~w(não nao n no nop nope)
  @negative_prefixes [
    "não,",
    "nao,",
    "não.",
    "nao.",
    "não quero",
    "nao quero",
    "não vou",
    "nao vou",
    "não obrigado",
    "nao obrigado"
  ]

  defp positive_answer?(norm) do
    norm in @positive or Enum.any?(@positive_prefixes, &String.starts_with?(norm, &1))
  end

  defp negative_answer?(norm) do
    norm in @negative or Enum.any?(@negative_prefixes, &String.starts_with?(norm, &1))
  end

  defp normalize(text) do
    text
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/[\s]+/, " ")
    |> String.replace(~r/[.!?,…]+$/, "")
  end

  @doc "Registers a group as pending (idempotent)."
  def register_pending(group_id) do
    insert_or_update(group_id, "pending")
  end

  @doc "Marks a group as active."
  def activate(group_id) do
    insert_or_update(group_id, "active")
  end

  @doc "Marks a group as left (declined)."
  def mark_left(group_id) do
    insert_or_update(group_id, "left")
  end

  @doc "Returns true when the group is active."
  def active?(group_id) do
    match?(%Group{status: "active"}, get_group(group_id))
  end

  @doc """
  Asks the bridge to leave the group (after `{:leave, text}` has been sent).
  """
  def request_leave(group_id) do
    BridgeClient.leave_group(group_id)
  end

  defp insert_or_update(group_id, status) do
    result =
      case get_group(group_id) do
        nil ->
          Repo.insert(%Group{group_id: group_id, status: status},
            on_conflict: [set: [status: status]],
            conflict_target: :group_id
          )

        %Group{} = group ->
          group
          |> Group.changeset(%{status: status})
          |> Repo.update()
      end

    case result do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "[Brain] Failed to update group #{group_id} to #{status}: #{inspect(reason)}"
        )

        :ok
    end
  end

  defp get_group(group_id) do
    Repo.get(Group, group_id)
  end
end
