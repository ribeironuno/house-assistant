defmodule Brain.Groups do
  require Logger

  @moduledoc """
  Multi-group (multi-tenant) activation context.

  A WhatsApp group goes through an approval flow:

  1. The bot is added to a group → status is `waiting_approval`.
     The bot is **silent** until an admin approves the group.
  2. An admin moves the group to `pending` via the backoffice.
     The bot introduces itself and asks "sim" / "não".
  3. On "sim" the group becomes `active` and the bot processes commands.
  4. On "não" the group becomes `left` and the bot asks the bridge to leave.
     The group can be re-added later; a new `group_join` event re-runs the intro.
  5. An admin can `block` any group at any time → the bot goes silent.

  ## Return contract

  All `handle_message/3` / `handle_join/1` calls return one of:

    - `{:reply, text}`  — send `text` back to the group
    - `:proceed`        — group is active; run the normal command pipeline
    - `:ignore`         — do nothing (waiting_approval, blocked, left, bot echoes, ...)
    - `{:leave, text}`  — send `text`, then tell the bridge to leave the group
  """

  import Ecto.Query

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

  @farewell_text """
                 [BOT] Até à próxima! 👋
                 """
                 |> String.trim_trailing()

  @ask_again_text """
                  [BOT] Ainda não percebi. Queres que fique ativo neste grupo? Responde "sim" ou "não".
                  """
                  |> String.trim_trailing()

  @doc "The intro message shown when a group is pending."
  def intro_text, do: @intro_text

  @doc "The farewell message shown before the bot leaves a group."
  def farewell_text, do: @farewell_text

  @doc "The confirmation message shown after a group replies 'sim'."
  def activated_text, do: @activated_text

  @doc "Prompt shown while a group is pending and sends something that is not sim/não."
  def ask_again_text, do: @ask_again_text

  # ── handle_join ──────────────────────────────────────────────────────────────

  @doc """
  Called when the bot is added to a group (bridge `group_join` event) or
  when the first message arrives from an unknown group.

  New groups start at `waiting_approval` — the bot stays silent until an admin
  approves them via the backoffice.
  """
  def handle_join(group_id, opts \\ %{}) do
    name = extract_name(opts)

    case Repo.get(Group, group_id) do
      nil ->
        Logger.info("[Brain] New group #{group_id} → waiting_approval")
        insert_group!(group_id, "waiting_approval", name)
        :ignore

      %Group{status: "waiting_approval"} = group ->
        maybe_update_name(group, name)
        :ignore

      %Group{status: "pending"} = group ->
        maybe_update_name(group, name)
        {:reply, @intro_text}

      %Group{status: "active"} = group ->
        maybe_update_name(group, name)
        :ignore

      %Group{status: "left"} = group ->
        Logger.info("[Brain] Bot re-added to left group #{group_id} → pending")
        maybe_update_name(group, name)
        update_status!(group, "pending")
        {:reply, @intro_text}

      %Group{status: "blocked"} = group ->
        maybe_update_name(group, name)
        :ignore
    end
  end

  # ── handle_message ───────────────────────────────────────────────────────────

  @doc """
  Gates every incoming group message through the activation state machine.
  """
  def handle_message(group_id, text, _sender, opts \\ %{}) do
    trimmed = String.trim(text || "")
    name = extract_name(opts)

    case Repo.get(Group, group_id) do
      nil ->
        Logger.info("[Brain] Unknown group #{group_id} → waiting_approval")
        insert_group!(group_id, "waiting_approval", name)
        :ignore

      %Group{status: "waiting_approval"} = group ->
        maybe_update_name(group, name)
        :ignore

      %Group{status: "pending"} = group ->
        maybe_update_name(group, name)
        handle_pending_activation(group_id, trimmed)

      %Group{status: "active"} = group ->
        maybe_update_name(group, name)
        :proceed

      %Group{status: "left"} = group ->
        maybe_update_name(group, name)
        :ignore

      %Group{status: "blocked"} = group ->
        maybe_update_name(group, name)
        :ignore
    end
  end

  # ── Admin actions (called by backoffice) ─────────────────────────────────────

  @doc "Admin approves a waiting_approval group → pending."
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

  @doc "Admin blocks a pending/active/left group."
  def block_group(group_id) do
    case Repo.get(Group, group_id) do
      %Group{status: status, group_id: gid}
      when status in ["pending", "active", "left", "waiting_approval"] ->
        update_status!(gid, "blocked")
        :ok

      %Group{} ->
        {:error, :already_blocked}

      nil ->
        {:error, :not_found}
    end
  end

  @doc "Admin unblocks a blocked group → pending."
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

  @doc "Deletes a group completely from the database."
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

  @doc "Marks a group as active (used by tests)."
  def activate(group_id) do
    case Repo.get(Group, group_id) do
      nil ->
        insert_group!(group_id, "active")

      %Group{} = group ->
        group
        |> Group.changeset(%{status: "active"})
        |> Repo.update!()
    end

    :ok
  end

  @doc "Marks a group as left (used by tests)."
  def mark_left(group_id) do
    case Repo.get(Group, group_id) do
      nil ->
        insert_group!(group_id, "left")

      %Group{} = group ->
        group
        |> Group.changeset(%{status: "left"})
        |> Repo.update!()
    end

    :ok
  end

  @doc "Registers a group as pending (used by tests)."
  def register_pending(group_id) do
    case Repo.get(Group, group_id) do
      nil ->
        insert_group!(group_id, "pending")

      %Group{} = group ->
        group
        |> Group.changeset(%{status: "pending"})
        |> Repo.update!()
    end

    :ok
  end

  @doc "Returns true when the group is active."
  def active?(group_id) do
    match?(%Group{status: "active"}, Repo.get(Group, group_id))
  end

  # ── Private ──────────────────────────────────────────────────────────────────

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

  @doc "Marks a group as left in DB without bridge API calls."
  def request_leave(group_id) do
    case Repo.get(Group, group_id) do
      nil ->
        insert_group!(group_id, "left")
        :ok

      %Group{status: "left"} ->
        :ok

      %Group{} = group ->
        update_status!(group, "left")
        :ok
    end
  end

  # ── Admin numbers ──────────────────────────────────────────────────────────────

  @doc "Returns the list of admin numbers for a group."
  def admins(group_id) do
    case Repo.get(Group, group_id) do
      %Group{admin_numbers: numbers} -> numbers
      nil -> []
    end
  end

  @doc "Adds an admin number to a group."
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

  @doc "Removes an admin number from a group."
  def remove_admin(group_id, number) do
    case Repo.get(Group, group_id) do
      %Group{} = group ->
        new_admins = group.admin_numbers || [] |> Enum.reject(&(&1 == number))

        group
        |> Group.changeset(%{admin_numbers: new_admins})
        |> Repo.update!()

        {:ok, new_admins}

      nil ->
        {:error, :not_found}
    end
  end

  @doc "Checks if a sender is an admin of the group."
  def is_admin?(group_id, sender) do
    sender in admins(group_id)
  end

  @doc "Returns a group by ID."
  def get_group(group_id) do
    Repo.get(Group, group_id)
  end
end
