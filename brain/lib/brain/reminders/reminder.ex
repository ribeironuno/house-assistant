defmodule Brain.Reminders.Reminder do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Ecto schema for scheduled WhatsApp reminders.
  """

  schema "reminders" do
    field(:text, :string)
    field(:group_id, :string)
    field(:created_by, :string)
    field(:remind_at, :utc_datetime)
    field(:sent_at, :utc_datetime)

    timestamps()
  end

  @doc """
  Builds a changeset for a reminder.
  """
  def changeset(reminder, attrs) do
    reminder
    |> cast(attrs, [:text, :group_id, :created_by, :remind_at, :sent_at])
    |> validate_required([:text, :group_id, :remind_at])
    |> update_change(:text, &String.trim/1)
    |> validate_length(:text, min: 1)
  end
end
