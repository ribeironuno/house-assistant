import { buildMsgKeys } from "./message-keys.js";

const recentSentMessageIds = new Set();

/**
 * Records a just-sent message so that the echo event arriving a few
 * milliseconds later is silently dropped.
 */
export function registerSentMessage(sentMsg, text) {
  const id = buildMsgKeys(sentMsg)[0] || sentMsg?.id?._serialized;
  if (id) {
    recentSentMessageIds.add(id);
    setTimeout(() => recentSentMessageIds.delete(id), 60000);
  }
}

/**
 * Returns true if the message was sent by the bot itself and should be
 * discarded to avoid an infinite reply loop.
 *
 * The `[BOT]` prefix is the only reliable loop-prevention marker — every
 * bot reply uses it. The sent-message ID cache is kept as a secondary
 * guard for messages sent through the /send endpoint.
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

  return false;
}
