defmodule Brain.Groups.Group do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Ecto schema for a WhatsApp group that has interacted with the bot.

  ## Statuses

  - `"waiting_approval"` — new group; the bot is silent until an admin approves.
  - `"pending"`          — approved by admin; the bot introduced itself and waits for "sim"/"não".
  - `"active"`           — the group opted in; the bot processes commands here.
  - `"left"`             — the group declined; the bot left the group (can be re-added later).
  - `"blocked"`          — admin blocked; the bot is fully silent.
  """

  @primary_key false
  schema "groups" do
    field(:group_id, :string, primary_key: true)
    field(:status, :string, default: "waiting_approval")
    field(:name, :string)
    field(:admin_numbers, {:array, :string}, default: [])

    timestamps()
  end

  @statuses ~w(waiting_approval pending active left blocked)

  def changeset(group, attrs) do
    group
    |> cast(attrs, [:group_id, :status, :name, :admin_numbers])
    |> validate_required([:group_id, :status])
    |> validate_inclusion(:status, @statuses)
  end
end
