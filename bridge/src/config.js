export const PORT = process.env.PORT || 3000;

export const ELIXIR_WEBHOOK_URL =
  process.env.ELIXIR_WEBHOOK_URL || "http://localhost:4000/webhook/whatsapp";

export const BRIDGE_AUTH_TOKEN = process.env.BRIDGE_AUTH_TOKEN?.trim() || "";
