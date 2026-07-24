defmodule BrainWeb.Router do
  use BrainWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BrainWeb do
    pipe_through :api

    post "/webhook/whatsapp", WebhookController, :create
  end
end
