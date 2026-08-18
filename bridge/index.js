/**
 * Bridge — WhatsApp ↔ Brain HTTP gateway
 *
 * Maintains WhatsApp session, forwards messages to brain, and exposes /send and /leave.
 * Loop prevention via isBridgeSelfMessage().
 */

import { config } from "dotenv";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

// Load .env from project root
const __dirname = dirname(fileURLToPath(import.meta.url));
config({ path: join(__dirname, "..", ".env") });

import qrcode from "qrcode-terminal";
import pkg from "whatsapp-web.js";

import { BRIDGE_AUTH_TOKEN, PORT } from "./src/config.js";
import { handleGroupJoin, handleIncomingMessage } from "./src/handler.js";
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
  process.exit(1);
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
  console.error(
    `[Bridge] Disconnected from WhatsApp: ${reason}. The bot is now offline — no messages are being processed.`,
  );
  isConnected = false;

  console.error(
    "[Bridge] Restarting in 5 seconds to recover the WhatsApp session...",
  );
  setTimeout(() => process.exit(1), 5_000);
});

client.on("message_create", async (message) => {
  await handleIncomingMessage(client, message);
});

client.on("group_join", async (notification) => {
  await handleGroupJoin(client, notification);
});

const app = createServer(client, () => isConnected, {
  authToken: BRIDGE_AUTH_TOKEN,
});

app.listen(PORT, () => {
  console.log(`[Bridge] Listening on port ${PORT}`);
  client.initialize();
});
