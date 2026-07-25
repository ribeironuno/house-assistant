defmodule Brain.Repo do
  use Ecto.Repo,
    otp_app: :brain,
    adapter: Ecto.Adapters.Postgres
end
