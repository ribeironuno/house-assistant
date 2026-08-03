import { buildMsgKeys } from "./message-keys.js";

const recentSentMessageIds = new Set();
const recentSentTexts = new Set();

const BOT_RESPONSE_PREFIXES = ["[BOT]", "✅", "🗑️", "🛒", "🧹"];

/**
 * Records a just-sent message in both caches so that the echo event
 * arriving a few milliseconds later is silently dropped.
 */
export function registerSentMessage(sentMsg, text) {
  const id = buildMsgKeys(sentMsg)[0] || sentMsg?.id?._serialized;
  if (id) {
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
 */
export function isBridgeSelfMessage(message) {
  const body = message.body ? message.body.trim() : "";

  if (body.startsWith("[BOT]")) {
    return true;
  }

  const msgKey = buildMsgKeys(message)[0] || message.id?._serialized;
  if (msgKey && recentSentMessageIds.has(msgKey)) {
    return true;
  }

  if (body && recentSentTexts.has(body)) {
    return true;
  }

  if (body && BOT_RESPONSE_PREFIXES.some((prefix) => body.startsWith(prefix))) {
    return true;
  }

  return false;
}
