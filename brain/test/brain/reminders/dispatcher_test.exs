defmodule Brain.Reminders.DispatcherTest do
  use BrainWeb.ConnCase

  alias Brain.Reminders.Dispatcher
  alias Brain.Reminders.Reminder
  alias Brain.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  defp create_reminder!(attrs) do
    {:ok, reminder} =
      Repo.insert(
        Reminder.changeset(%Reminder{}, %{
          text: Keyword.get(attrs, :text, "pagar conta"),
          remind_at: Keyword.get(attrs, :remind_at, DateTime.utc_now()),
          created_by: "user_1",
          group_id: "group_1"
        })
      )

    reminder
  end

  test "dispatch sends a due reminder and marks it sent" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    reminder = create_reminder!(remind_at: DateTime.add(now, -60, :second))

    Dispatcher.dispatch_due_reminders(now)

    updated = Repo.get!(Reminder, reminder.id)
    assert updated.sent_at == now
  end

  test "dispatch does not send reminders that are already sent" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    reminder = create_reminder!(remind_at: DateTime.add(now, -60, :second))
    Repo.update!(Reminder.changeset(reminder, %{sent_at: now}))

    Dispatcher.dispatch_due_reminders(now)

    updated = Repo.get!(Reminder, reminder.id)
    assert updated.sent_at == now
  end

  test "dispatch does not send future reminders" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    reminder = create_reminder!(remind_at: DateTime.add(now, 3600, :second))

    Dispatcher.dispatch_due_reminders(now)

    updated = Repo.get!(Reminder, reminder.id)
    assert is_nil(updated.sent_at)
  end

  test "dispatch catches up reminders missed while offline" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    r1 = create_reminder!(remind_at: DateTime.add(now, -3600, :second))
    r2 = create_reminder!(remind_at: DateTime.add(now, -60, :second))

    Dispatcher.dispatch_due_reminders(now)

    assert Repo.get!(Reminder, r1.id).sent_at == now
    assert Repo.get!(Reminder, r2.id).sent_at == now
  end

  test "dispatch leaves reminder unsent when bridge delivery fails (retry on next tick)" do
    original = Application.get_env(:brain, :send_outgoing_messages)
    Application.put_env(:brain, :send_outgoing_messages, true)
    on_exit(fn -> Application.put_env(:brain, :send_outgoing_messages, original) end)

    # Point the bridge URL at a closed port so the HTTP call fails fast.
    original_url = System.get_env("BRIDGE_SEND_URL")
    System.put_env("BRIDGE_SEND_URL", "http://127.0.0.1:59999/send")

    on_exit(fn ->
      case original_url do
        nil -> System.delete_env("BRIDGE_SEND_URL")
        url -> System.put_env("BRIDGE_SEND_URL", url)
      end
    end)

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    reminder = create_reminder!(remind_at: DateTime.add(now, -60, :second))

    Dispatcher.dispatch_due_reminders(now)

    updated = Repo.get!(Reminder, reminder.id)
    assert is_nil(updated.sent_at)
  end
end
