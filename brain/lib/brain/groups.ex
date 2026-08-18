defmodule Brain.Groups do
  require Logger

  @moduledoc """
  Multi-group activation state machine.

  Flow: waiting_approval → pending → active (via "sim") / left (via "não").
  Admins can additionally block/unblock a group at any point, which
  pauses processing without touching its data, and can permanently
  delete a group (which does remove its data) via `delete_group/1`.

  Returns: `{:reply, text}`, `{:leave, text}`, `:proceed`, or `:ignore`.
  """

  import Ecto.Query

  alias Brain.Repo
  alias Brain.Groups.Group
  alias Brain.WhatsApp.BridgeClient

  @statuses ~w(waiting_approval pending active left blocked)
  def statuses, do: @statuses

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

  @farewell_text """
                 [BOT] Até à próxima! 👋
                 """
                 |> String.trim_trailing()

  @ask_again_text """
                  [BOT] Ainda não percebi. Queres que fique ativo neste grupo? Responde "sim" ou "não".
                  """
                  |> String.trim_trailing()

  def intro_text, do: @intro_text
  def farewell_text, do: @farewell_text
  def activated_text, do: @activated_text
  def ask_again_text, do: @ask_again_text

  @spec handle_join(String.t(), map()) :: {:reply, String.t()} | :ignore
  def handle_join(group_id, opts \\ %{}) do
    with_group(group_id, opts, &join_action/1)
  end

  @spec handle_message(String.t(), String.t() | nil, term(), map()) ::
          {:reply, String.t()} | {:leave, String.t()} | :proceed | :ignore
  def handle_message(group_id, text, _sender, opts \\ %{}) do
    trimmed = String.trim(text || "")
    with_group(group_id, opts, &message_action(&1, trimmed))
  end

  defp with_group(group_id, opts, action) do
    name = extract_name(opts)

    case Repo.get(Group, group_id) do
      nil ->
        Logger.info("[Brain] Unknown group #{group_id} → waiting_approval")
        insert_group!(group_id, "waiting_approval", name)
        :ignore

      %Group{} = group ->
        maybe_update_name(group, name)
        action.(group)
    end
  end

  defp join_action(%Group{status: "pending"}), do: {:reply, @intro_text}

  defp join_action(%Group{status: "left"} = group) do
    Logger.info("[Brain] Bot re-added to left group #{group.group_id} → pending")
    update_status!(group, "pending")
    {:reply, @intro_text}
  end

  # waiting_approval, active, blocked: nothing to do on (re)join
  defp join_action(%Group{}), do: :ignore

  defp message_action(%Group{status: "pending", group_id: group_id}, text) do
    handle_pending_activation(group_id, text)
  end

  defp message_action(%Group{status: "active"}, _text), do: :proceed

  # waiting_approval, left, blocked: no processing while in these states
  defp message_action(%Group{}, _text), do: :ignore

  @spec handle_pending_activation(String.t(), String.t()) ::
          {:reply, String.t()} | {:leave, String.t()}
  def handle_pending_activation(group_id, text) do
    normalized = String.downcase(text) |> String.trim()

    cond do
      String.starts_with?(normalized, "sim") ->
        update_status!(group_id, "active")
        {:reply, @activated_text}

      String.starts_with?(normalized, "não") or String.starts_with?(normalized, "nao") ->
        update_status!(group_id, "left")
        {:leave, @farewell_text}

      true ->
        {:reply, @ask_again_text}
    end
  end

  @spec approve_group(String.t()) :: :ok | {:error, :not_waiting_approval} | {:error, :not_found}
  def approve_group(group_id) do
    case Repo.get(Group, group_id) do
      %Group{status: "waiting_approval"} = group ->
        update_status!(group, "pending")
        BridgeClient.send_message(group_id, @intro_text)
        :ok

      %Group{} ->
        {:error, :not_waiting_approval}

      nil ->
        {:error, :not_found}
    end
  end

  @spec block_group(String.t()) :: :ok | {:error, :already_blocked} | {:error, :not_found}
  def block_group(group_id) do
    case Repo.get(Group, group_id) do
      %Group{status: status} = group
      when status in ["pending", "active", "left", "waiting_approval"] ->
        update_status!(group, "blocked")
        :ok

      %Group{} ->
        {:error, :already_blocked}

      nil ->
        {:error, :not_found}
    end
  end

  @spec unblock_group(String.t()) :: :ok | {:error, :not_blocked} | {:error, :not_found}
  def unblock_group(group_id) do
    case Repo.get(Group, group_id) do
      %Group{status: "blocked"} = group ->
        update_status!(group, "pending")
        BridgeClient.send_message(group_id, @intro_text)
        :ok

      %Group{} ->
        {:error, :not_blocked}

      nil ->
        {:error, :not_found}
    end
  end

  @spec delete_group(String.t()) :: :ok | {:error, term()} | {:error, :not_found}
  def delete_group(group_id) do
    case Repo.get(Group, group_id) do
      %Group{} = group ->
        Repo.transaction(fn ->
          from(s in Brain.ShoppingList.Item, where: s.group_id == ^group_id) |> Repo.delete_all()
          from(p in Brain.Pantry.Item, where: p.group_id == ^group_id) |> Repo.delete_all()
          from(r in Brain.Reminders.Reminder, where: r.group_id == ^group_id) |> Repo.delete_all()
          from(m in Brain.Menu.WeeklyMenu, where: m.group_id == ^group_id) |> Repo.delete_all()
          from(f in Brain.Menu.MealFeedback, where: f.group_id == ^group_id) |> Repo.delete_all()

          Repo.delete!(group)
        end)
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      nil ->
        {:error, :not_found}
    end
  end

  @spec activate(String.t()) :: :ok
  def activate(group_id), do: upsert_status!(group_id, "active")

  @spec mark_left(String.t()) :: :ok
  def mark_left(group_id), do: upsert_status!(group_id, "left")

  @spec register_pending(String.t()) :: :ok
  def register_pending(group_id), do: upsert_status!(group_id, "pending")

  defp upsert_status!(group_id, status) do
    case Repo.get(Group, group_id) do
      nil -> insert_group!(group_id, status)
      %Group{} = group -> update_status!(group, status)
    end

    :ok
  end

  @spec active?(String.t()) :: boolean()
  def active?(group_id) do
    match?(%Group{status: "active"}, Repo.get(Group, group_id))
  end

  @spec request_leave(String.t()) :: :ok
  def request_leave(group_id) do
    case Repo.get(Group, group_id) do
      nil -> insert_group!(group_id, "left")
      %Group{status: "left"} -> :ok
      %Group{} = group -> update_status!(group, "left")
    end

    :ok
  end

  @spec get_group(String.t()) :: Group.t() | nil
  def get_group(group_id) do
    Repo.get(Group, group_id)
  end

  defp insert_group!(group_id, status, name \\ nil) do
    %Group{}
    |> Group.changeset(%{group_id: group_id, status: status, name: name})
    |> Repo.insert!()
  end

  defp maybe_update_name(_group, nil), do: :ok
  defp maybe_update_name(_group, ""), do: :ok

  defp maybe_update_name(%Group{} = group, name) when is_binary(name) do
    if group.name != name do
      group
      |> Group.changeset(%{name: name})
      |> Repo.update!()
    end
  end

  defp update_status!(%Group{} = group, status) do
    group
    |> Group.changeset(%{status: status})
    |> Repo.update!()
  end

  defp update_status!(group_id, status) when is_binary(group_id) do
    Repo.get!(Group, group_id)
    |> Group.changeset(%{status: status})
    |> Repo.update!()
  end

  defp extract_name(%{group_name: name}) when is_binary(name) and name != "", do: name
  defp extract_name(%{"group_name" => name}) when is_binary(name) and name != "", do: name
  defp extract_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp extract_name(%{"name" => name}) when is_binary(name) and name != "", do: name
  defp extract_name(_), do: nil

  @spec admins(String.t()) :: [String.t()]
  def admins(group_id) do
    case Repo.get(Group, group_id) do
      %Group{admin_numbers: numbers} -> numbers
      nil -> []
    end
  end

  @spec add_admin(String.t(), String.t()) :: {:ok, [String.t()]} | {:error, :not_found}
  def add_admin(group_id, number) do
    case Repo.get(Group, group_id) do
      %Group{} = group ->
        current = group.admin_numbers || []
        new_admins = Enum.uniq(current ++ [number])

        group
        |> Group.changeset(%{admin_numbers: new_admins})
        |> Repo.update!()

        {:ok, new_admins}

      nil ->
        {:error, :not_found}
    end
  end

  @spec remove_admin(String.t(), String.t()) :: {:ok, [String.t()]} | {:error, :not_found}
  def remove_admin(group_id, number) do
    case Repo.get(Group, group_id) do
      %Group{} = group ->
        new_admins = (group.admin_numbers || []) |> Enum.reject(&(&1 == number))

        group
        |> Group.changeset(%{admin_numbers: new_admins})
        |> Repo.update!()

        {:ok, new_admins}

      nil ->
        {:error, :not_found}
    end
  end

  @spec is_admin?(String.t(), String.t()) :: boolean()
  def is_admin?(group_id, sender) do
    sender in admins(group_id)
  end
end
