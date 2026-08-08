import express from "express";
import { registerSentMessage } from "./loop-prevention.js";
import crypto from "crypto";

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
 * Creates the Express HTTP server with health check and send endpoints.
 *
 * @param {object} client - The whatsapp-web.js Client instance.
 * @param {function} isConnectedFn - Returns current connection state.
 * @param {object} options
 * @param {string} options.targetGroupId
 * @param {string} options.authToken
 * @returns {import("express").Express}
 */
export function createServer(
  client,
  isConnectedFn,
  { targetGroupId, authToken },
) {
  const app = express();
  app.use(express.json());

  const hasAuth = Boolean(authToken);

  app.get("/health", (_, res) => {
    res.json({
      status: "ok",
      connected: isConnectedFn(),
    });
  });

  app.post("/send", (req, res, next) => {
    if (hasAuth) {
      const header = req.headers.authorization;
      if (!header || !header.startsWith("Bearer ")) {
        return res.status(401).json({ error: "Missing or invalid token" });
      }
      const token = header.slice(7);
      if (!timingSafeEqual(token, authToken)) {
        return res.status(403).json({ error: "Invalid token" });
      }
    }

    const { to, text } = req.body;

    if (!to || typeof text !== "string" || !text) {
      return res.status(400).json({ error: "Missing 'to' or 'text'" });
    }

    if (to !== targetGroupId) {
      return res
        .status(400)
        .json({ error: "Message target does not match the configured group" });
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

  return app;
}
