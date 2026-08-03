import express from "express";
import { registerSentMessage } from "./loop-prevention.js";

/**
 * Creates the Express HTTP server with health check and send endpoints.
 *
 * @param {object} client - The whatsapp-web.js Client instance.
 * @param {function} isConnectedFn - Returns current connection state.
 * @param {object} options
 * @param {string} options.targetGroupId
 * @returns {import("express").Express}
 */
export function createServer(client, isConnectedFn, { targetGroupId }) {
  const app = express();
  app.use(express.json());

  app.get("/health", (_, res) => {
    res.json({
      status: "ok",
      connected: isConnectedFn(),
      target_group_id: targetGroupId || null,
    });
  });

  app.post("/send", async (req, res) => {
    const { to, text } = req.body;

    if (!to || !text) {
      return res.status(400).json({ error: "Missing 'to' or 'text'" });
    }

    if (!isConnectedFn()) {
      return res.status(503).json({ error: "WhatsApp not connected" });
    }

    try {
      const sentMsg = await client.sendMessage(to, text);
      registerSentMessage(sentMsg, text);
      console.log(`[Bridge] Sent message to [${to}]: "${text}"`);
      res.json({ status: "ok" });
    } catch (err) {
      console.error("[Bridge] Error in sendMessage:", err);
      res.status(500).json({ error: err.message });
    }
  });

  return app;
}
