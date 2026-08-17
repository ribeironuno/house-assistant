import crypto from "crypto";
import express from "express";
import { registerSentMessage } from "./loop-prevention.js";

/**
 * Constant-time string comparison to prevent timing attacks.
 */
function timingSafeEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return false;
  const bufA = Buffer.from(a, "utf8");
  const bufB = Buffer.from(b, "utf8");
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

/**
 * Creates the Express HTTP server with health check, send, and leave endpoints.
 *
 * @param {object} client - The whatsapp-web.js Client instance.
 * @param {function} isConnectedFn - Returns current connection state.
 * @param {object} options
 * @param {string} options.authToken - Shared secret for /send and /leave (MUST be set in production).
 * @returns {import("express").Express}
 */
export function createServer(client, isConnectedFn, { authToken }) {
  if (!authToken) {
    throw new Error("BRIDGE_AUTH_TOKEN must be set");
  }

  const app = express();
  app.use(express.json());

  // ---------------------------------------------------------------------------
  // Shared Bearer-token auth middleware (applies to /send and /leave).
  // ---------------------------------------------------------------------------
  function requireToken(req, res, next) {
    const header = req.headers.authorization;
    if (!header || !header.startsWith("Bearer ")) {
      return res.status(401).json({ error: "Missing or invalid token" });
    }

    const token = header.slice(7);
    if (!timingSafeEqual(token, authToken)) {
      return res.status(403).json({ error: "Invalid token" });
    }

    return next();
  }

  // ---------------------------------------------------------------------------
  // GET /health
  // ---------------------------------------------------------------------------
  app.get("/health", (_, res) => {
    res.json({ status: "ok", connected: isConnectedFn() });
  });

  // ---------------------------------------------------------------------------
  // POST /send — send a WhatsApp message to any group.
  // ---------------------------------------------------------------------------
  app.post("/send", requireToken, (req, res, next) => {
    const { to, text } = req.body;

    if (!to || !to.endsWith("@g.us") || typeof text !== "string" || !text) {
      return res
        .status(400)
        .json({ error: "Missing or invalid 'to' or 'text'" });
    }

    if (!isConnectedFn()) {
      return res.status(503).json({ error: "WhatsApp not connected" });
    }

    next();
  });

  app.post("/send", async (req, res) => {
    const { to, text } = req.body;

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

  // ---------------------------------------------------------------------------
  // POST /leave — tell the bridge to leave a group.
  // ---------------------------------------------------------------------------
  app.post("/leave", requireToken, async (req, res) => {
    const { group_id } = req.body;

    if (!group_id || !group_id.endsWith("@g.us")) {
      return res.status(400).json({ error: "Missing or invalid 'group_id'" });
    }

    if (!isConnectedFn()) {
      return res.status(503).json({ error: "WhatsApp not connected" });
    }

    try {
      console.log(`[Bridge] Leaving group [${group_id}]`);
      const chat = await client.getChatById(group_id);
      await chat.leave();
      res.json({ status: "ok" });
    } catch (err) {
      console.error("[Bridge] Error leaving group:", err);
      res.status(500).json({ error: err.message });
    }
  });

  return app;
}
