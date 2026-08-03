import { TARGET_GROUP_ID, ELIXIR_WEBHOOK_URL } from "./config.js";
import { isBridgeSelfMessage } from "./loop-prevention.js";
import { downloadMediaFixed } from "./media-download.js";

/**
 * Handles every message_create event from WhatsApp.
 *
 * Flow:
 *   1. Drop empty messages.
 *   2. Drop messages identified as bot echoes (loop prevention).
 *   3. Resolve the real group JID.
 *   4. Drop messages that don't belong to the configured TARGET_GROUP_ID.
 *   5. Forward the message payload to the Elixir brain.
 */
export async function handleIncomingMessage(client, message) {
  if (!message.body && !message.hasMedia) return;

  if (isBridgeSelfMessage(message)) {
    console.log("[Bridge] Discarding bot response message:", message.body);
    return;
  }

  const groupId = message.fromMe ? message.to : message.from;

  if (TARGET_GROUP_ID && groupId !== TARGET_GROUP_ID) {
    return;
  }

  let mediaData = null;
  if (message.hasMedia) {
    try {
      console.log(
        "[Bridge] Attempting media download for message:",
        message.id?.id,
      );
      const downloaded = await downloadMediaFixed(client, message);
      if (downloaded && downloaded.data) {
        mediaData = {
          mimetype: downloaded.mimetype,
          data: downloaded.data,
          filename: downloaded.filename || null,
        };
        console.log(
          `[Bridge] Downloaded media (${downloaded.mimetype}, ${downloaded.data.length} chars base64)`,
        );
      } else if (downloaded && downloaded.error) {
        console.error(
          `[Bridge] Media download failed: ${downloaded.error}${downloaded.stage ? " (stage: " + downloaded.stage + ")" : ""}`,
        );
        if (downloaded.message) console.error(`  ${downloaded.message}`);
      } else {
        console.log(
          "[Bridge] Media download returned no data for message:",
          message.id?.id,
        );
      }
    } catch (err) {
      console.error(
        "[Bridge] Failed to download media:",
        err.message,
        err.stack,
      );
    }
  }

  console.log("[Bridge] Processing incoming command from phone/group", {
    group: groupId,
    sender: message.author ?? message.from,
    fromMe: message.fromMe,
    text: message.body,
    hasMedia: !!mediaData,
  });

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
