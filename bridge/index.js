/**
 * Bridge — WhatsApp ↔ Brain HTTP gateway
 *
 * Responsibilities:
 *   - Maintain a WhatsApp Web session via whatsapp-web.js.
 *   - Forward incoming group messages to the Elixir brain via POST /webhook/whatsapp.
 *   - Expose POST /send so the brain can push replies back to the group.
 *   - Prevent echo loops: because the bridge and the owner's phone share the same
 *     WhatsApp account, every bot reply also fires a message_create event.
 *     Loop prevention is handled by isBridgeSelfMessage() — see details below.
 *
 * Environment variables:
 *   PORT              — HTTP port (default: 3000)
 *   ELIXIR_WEBHOOK_URL — Brain webhook URL (default: http://localhost:4000/webhook/whatsapp)
 *   TARGET_GROUP_ID   — WhatsApp group JID to accept messages from (e.g. 120363...@g.us)
 */

import express from "express";
import qrcode from "qrcode-terminal";
import pkg from "whatsapp-web.js";

const { Client, LocalAuth } = pkg;

const PORT = process.env.PORT || 3000;
const ELIXIR_WEBHOOK_URL =
  process.env.ELIXIR_WEBHOOK_URL || "http://localhost:4000/webhook/whatsapp";

const TARGET_GROUP_ID =
  process.env.TARGET_GROUP_ID?.trim() || "";

let isConnected = false;

// ---------------------------------------------------------------------------
// Loop prevention
//
// The bridge and the owner's phone share the same WhatsApp account, so every
// message sent by the bot is also received by the bridge as a message_create
// event. We use three independent checks (in order of reliability):
//
//   1. [BOT] prefix  — all bot replies start with "[BOT]"; authoritative and
//                      stateless, so it works even after a bridge restart.
//   2. Message ID    — the ID returned by client.sendMessage, kept for 60 s.
//   3. Exact text    — the raw text we just sent, kept for 60 s (fallback).
//   4. Known prefixes — legacy emoji/keyword prefixes (belt-and-suspenders).
// ---------------------------------------------------------------------------

/** Short-lived sets that track recently sent messages for loop detection. */
const recentSentMessageIds = new Set();
const recentSentTexts = new Set();

const BOT_RESPONSE_PREFIXES = ["[BOT]", "✅", "🗑️", "🛒", "🧹"];

/**
 * Records a just-sent message in both caches so that the echo event
 * arriving a few milliseconds later is silently dropped.
 *
 * @param {object} sentMsg - The message object returned by client.sendMessage.
 * @param {string} text    - The raw text that was sent.
 */
function registerSentMessage(sentMsg, text) {
  if (sentMsg?.id?._serialized) {
    const id = sentMsg.id._serialized;
    recentSentMessageIds.add(id);
    setTimeout(() => recentSentMessageIds.delete(id), 60000);
  }

  if (text) {
    const trimmed = text.trim();
    recentSentTexts.add(trimmed);
    setTimeout(() => recentSentTexts.delete(trimmed), 60000);
  }
}

/**
 * Returns true if the message was sent by the bot itself and should be
 * discarded to avoid an infinite reply loop.
 *
 * @param {object} message - A whatsapp-web.js Message object.
 * @returns {boolean}
 */
function isBridgeSelfMessage(message) {
  const body = message.body ? message.body.trim() : "";

  // Check 1: [BOT] prefix — authoritative, stateless marker on all bot replies
  if (body.startsWith("[BOT]")) {
    return true;
  }

  // Check 2: Exact message ID match (stateful, 60 s window)
  if (
    message.id?._serialized &&
    recentSentMessageIds.has(message.id._serialized)
  ) {
    return true;
  }

  // Check 3: Exact text match (stateful, 60 s window)
  if (body && recentSentTexts.has(body)) {
    return true;
  }

  // Check 4: Known bot-output prefixes (fallback)
  if (body && BOT_RESPONSE_PREFIXES.some((prefix) => body.startsWith(prefix))) {
    return true;
  }

  return false;
}

// ---------------------------------------------------------------------------
// WhatsApp client
// ---------------------------------------------------------------------------

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
  await handleIncomingMessage(message);
});

/**
 * Handles every message_create event from WhatsApp.
 *
 * Flow:
 *   1. Drop empty messages.
 *   2. Drop messages identified as bot echoes (loop prevention).
 *   3. Resolve the real group JID — whatsapp-web.js swaps message.from/message.to
 *      for self-sent messages, so we pick the correct field based on fromMe.
 *   4. Drop messages that don't belong to the configured TARGET_GROUP_ID.
 *   5. Forward the message payload to the Elixir brain.
 *
 * @param {object} message - A whatsapp-web.js Message object.
 */
async function handleIncomingMessage(message) {
  if (!message.body && !message.hasMedia) return;

  // Step 2: Drop bot echoes
  if (isBridgeSelfMessage(message)) {
    console.log("[Bridge] Discarding bot response message:", message.body);
    return;
  }

  // Step 3: Resolve the real group JID.
  // When fromMe:true, whatsapp-web.js sets:
  //   message.from = the sender's own JID (your number)
  //   message.to   = the destination (the group)
  // For messages from others: message.from = the group, message.to = your JID.
  const groupId = message.fromMe ? message.to : message.from;

  // Step 4: Filter by target group
  if (TARGET_GROUP_ID && groupId !== TARGET_GROUP_ID) {
    return;
  }

  let mediaData = null;
  if (message.hasMedia) {
    try {
      const downloaded = await message.downloadMedia();
      if (downloaded && downloaded.data) {
        mediaData = {
          mimetype: downloaded.mimetype,
          data: downloaded.data,
          filename: downloaded.filename || null,
        };
        console.log(`[Bridge] Downloaded media (${downloaded.mimetype}, ${downloaded.data.length} chars base64)`);
      }
    } catch (err) {
      console.error("[Bridge] Failed to download media:", err.message);
    }
  }

  console.log("[Bridge] Processing incoming command from phone/group", {
    group: groupId,
    sender: message.author ?? message.from,
    fromMe: message.fromMe,
    text: message.body,
    hasMedia: !!mediaData,
  });

  // Step 5: Forward to brain
  try {
    const response = await fetch(ELIXIR_WEBHOOK_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        group_id: groupId,
        sender: message.author ?? message.from,
        text: message.body || "",
        media: mediaData,
        from_me: message.fromMe,
        timestamp: message.timestamp,
      }),
    });

    if (!response.ok) {
      console.error(`[Bridge] Webhook returned HTTP ${response.status}`);
    }
  } catch (err) {
    console.error(
      "[Bridge] Failed to send webhook to Elixir brain:",
      err.message,
    );
  }
}

// ---------------------------------------------------------------------------
// HTTP API
// ---------------------------------------------------------------------------

const app = express();
app.use(express.json());

/**
 * GET /health
 * Returns the current connection status and configured group ID.
 */
app.get("/health", (_, res) => {
  res.json({
    status: "ok",
    connected: isConnected,
    target_group_id: TARGET_GROUP_ID || null,
  });
});

/**
 * POST /send
 * Sends a message to a WhatsApp chat/group.
 *
 * Body: { "to": "<JID>", "text": "<message>" }
 * Called by the Elixir brain after processing a command.
 */
app.post("/send", async (req, res) => {
  const { to, text } = req.body;

  if (!to || !text) {
    return res.status(400).json({ error: "Missing 'to' or 'text'" });
  }

  if (!isConnected) {
    return res.status(503).json({ error: "WhatsApp not connected" });
  }

  try {
    const sentMsg = await client.sendMessage(to, text);
    // Register so the echo event is dropped by isBridgeSelfMessage
    registerSentMessage(sentMsg, text);

    console.log(`[Bridge] Sent message to [${to}]: "${text}"`);
    res.json({ status: "ok" });
  } catch (err) {
    console.error("[Bridge] Error in sendMessage:", err);
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, () => {
  console.log(`[Bridge] Listening on port ${PORT}`);
  client.initialize();
});
