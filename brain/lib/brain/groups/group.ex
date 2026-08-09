defmodule Brain.Groups.Group do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Ecto schema for a WhatsApp group that has interacted with the bot.

  ## Statuses

  - `"pending"` — the bot introduced itself and is waiting for a "sim"/"não" answer.
  - `"active"`  — the group opted in; the bot processes commands here.
  - `"left"`    — the group declined; the bot left the group (can be re-added later).
  """

  @primary_key false
  schema "groups" do
    field(:group_id, :string, primary_key: true)
    field(:status, :string, default: "pending")

    timestamps()
  end

  @statuses ~w(pending active left)

  def changeset(group, attrs) do
    group
    |> cast(attrs, [:group_id, :status])
    |> validate_required([:group_id, :status])
    |> validate_inclusion(:status, @statuses)
  end
end
