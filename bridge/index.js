import express from "express";
import qrcode from "qrcode-terminal";
import pkg from "whatsapp-web.js";

const { Client, LocalAuth } = pkg;

const PORT = process.env.PORT || 3000;

const ELIXIR_WEBHOOK_URL =
  process.env.ELIXIR_WEBHOOK_URL || "http://localhost:4000/webhook/whatsapp";

// const TARGET_GROUP_ID = process.env.TARGET_GROUP_ID?.trim() ?? "";
const TARGET_GROUP_ID = "";

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
  console.log("Scan this QR:");
  qrcode.generate(qr, { small: true });
});

client.on("authenticated", () => {
  console.log("Authenticated");
});

client.on("ready", async () => {
  console.log("WhatsApp ready!");
  isConnected = true;
});

client.on("disconnected", (reason) => {
  console.log("Disconnected:", reason);
  isConnected = false;
});

client.on("change_state", (state) => {
  console.log("STATE:", state);
});

client.on("loading_screen", (percent, message) => {
  console.log("LOADING", percent, message);
});

client.on("message_create", async (message) => {
  console.log("[Bridge] message_create", {
    from: message.from,
    author: message.author,
    fromMe: message.fromMe,
    body: message.body,
  });

  await handleIncomingMessage(message);
});

async function handleIncomingMessage(message) {
  // if (!message.body) {
  //   return;
  // }

  // if (message.from !== TARGET_GROUP_ID) {
  //   return;
  // }

  console.log("[Bridge] Processing target group message", {
    group: message.from,
    sender: message.author ?? message.from,
    fromMe: message.fromMe,
    text: message.body,
  });

  try {
    const response = await fetch(ELIXIR_WEBHOOK_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        group_id: message.from,
        sender: message.author ?? message.from,
        text: message.body,
        from_me: message.fromMe,
        timestamp: message.timestamp,
      }),
    });

    if (!response.ok) {
      console.error(`[Bridge] Webhook returned HTTP ${response.status}`);
    }
  } catch (err) {
    console.error("[Bridge] Failed to send webhook:", err);
  }
}

const app = express();

app.use(express.json());

app.get("/health", (_, res) => {
  res.json({
    status: "ok",
    connected: isConnected,
    target_group_id: TARGET_GROUP_ID || null,
  });
});

app.post("/send", async (req, res) => {
  const { to, text } = req.body;

  if (!to || !text) {
    return res.status(400).json({
      error: "Missing 'to' or 'text'",
    });
  }

  if (!isConnected) {
    return res.status(503).json({
      error: "WhatsApp not connected",
    });
  }

  try {
    await client.sendMessage(to, text);

    res.json({
      status: "ok",
    });
  } catch (err) {
    res.status(500).json({
      error: err.message,
    });
  }
});

app.listen(PORT, () => {
  console.log(`Listening on ${PORT}`);

  client.initialize();
});
