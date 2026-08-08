/**
 * Bridge — WhatsApp ↔ Brain HTTP gateway
 *
 * Responsibilities:
 *   - Maintain a WhatsApp Web session via whatsapp-web.js.
 *   - Forward incoming group messages to the Elixir brain via POST /webhook/whatsapp.
 *   - Expose POST /send so the brain can push replies back to the group.
 *   - Prevent echo loops: because the bridge and the owner's phone share the same
 *     WhatsApp account, every bot reply also fires a message_create event.
 *     Loop prevention is handled by isBridgeSelfMessage() — see loop-prevention.js.
 *
 * Environment variables:
 *   PORT              — HTTP port (default: 3000)
 *   ELIXIR_WEBHOOK_URL — Brain webhook URL (default: http://localhost:4000/webhook/whatsapp)
 *   TARGET_GROUP_ID   — WhatsApp group JID to accept messages from (e.g. 120363...@g.us)
 */

import qrcode from "qrcode-terminal";
import pkg from "whatsapp-web.js";

import { PORT, TARGET_GROUP_ID } from "./src/config.js";
import { handleIncomingMessage } from "./src/handler.js";
import { createServer } from "./src/server.js";

const { Client, LocalAuth } = pkg;

process.on("unhandledRejection", (reason) => {
  console.error(
    "[Bridge] Unhandled promise rejection (keeping process alive):",
    reason,
  );
});

process.on("uncaughtException", (err) => {
  console.error("[Bridge] Uncaught exception:", err);
});

let isConnected = false;

const client = new Client({
  authStrategy: new LocalAuth({ clientId: "house-assistant" }),
  puppeteer: {
    headless: true,
    args: ["--no-sandbox", "--disable-setuid-sandbox"],
  },
  webVersionCache: {
    type: "remote",
    remotePath:
      "https://raw.githubusercontent.com/wppconnect-team/wa-version/main/html/{version}.html",
  },
});

client.on("qr", (qr) => {
  console.log("[Bridge] Scan this QR code:");
  qrcode.generate(qr, { small: true });
});

client.on("authenticated", () => {
  console.log("[Bridge] Authenticated successfully");
});

client.on("ready", async () => {
  console.log("[Bridge] WhatsApp client ready!");
  isConnected = true;
});

client.on("disconnected", (reason) => {
  console.log("[Bridge] Disconnected:", reason);
  isConnected = false;
});

client.on("message_create", async (message) => {
  await handleIncomingMessage(client, message);
});

const app = createServer(client, () => isConnected, { targetGroupId: TARGET_GROUP_ID });

app.listen(PORT, () => {
  console.log(`[Bridge] Listening on port ${PORT}`);
  client.initialize();
});
