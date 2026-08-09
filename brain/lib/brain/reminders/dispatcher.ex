defmodule Brain.Reminders.Dispatcher do
  use GenServer
  import Ecto.Query
  require Logger

  alias Brain.Repo
  alias Brain.Reminders.Reminder
  alias Brain.WhatsApp.BridgeClient

  @moduledoc """
  Periodically sends due reminders through the WhatsApp Bridge.
  """

  @default_interval_ms 30_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval_ms = Keyword.get(opts, :interval_ms, configured_interval_ms())
    state = %{interval_ms: interval_ms}
    schedule_tick(0)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    dispatch_due_reminders()
    schedule_tick(state.interval_ms)
    {:noreply, state}
  end

  @doc """
  Sends all unsent reminders whose scheduled time has passed.
  """
  def dispatch_due_reminders(now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)

    Reminder
    |> where([r], is_nil(r.sent_at) and r.remind_at <= ^now)
    |> order_by([r], asc: r.remind_at)
    |> Repo.all()
    |> Enum.each(&send_reminder(&1, now))
  end

  defp send_reminder(%Reminder{} = reminder, now) do
    case BridgeClient.send_message(reminder.group_id, "[BOT] 🔔 Lembrete: #{reminder.text}") do
      :ok ->
        reminder
        |> Reminder.changeset(%{sent_at: now})
        |> Repo.update()

      {:error, reason} ->
        Logger.error("[Brain] Failed to send reminder #{reminder.id}: #{inspect(reason)}")
    end
  end

  defp schedule_tick(delay_ms) do
    Process.send_after(self(), :tick, delay_ms)
  end

  defp configured_interval_ms do
    Application.get_env(:brain, :reminder_dispatch_interval_ms, @default_interval_ms)
  end
end
