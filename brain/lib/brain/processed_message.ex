defmodule Brain.ProcessedMessage do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Tracks processed WhatsApp message IDs for idempotency.
  """

  @primary_key false
  schema "processed_messages" do
    field(:message_id, :string, primary_key: true)
    field(:processed_at, :utc_datetime)

    # No timestamps - we only need processed_at
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:message_id])
    |> validate_required([:message_id])
    |> unique_constraint(:message_id)
  end
end
