import { buildMsgKeys } from "./message-keys.js";

/**
 * Downloads media for a message using a reconstructed store key.
 *
 * whatsapp-web.js v1.34.7 has a bug where getMessageModel strips the
 * `_serialized` prototype getter from the MsgKey via Object.assign,
 * so `_serialized` is always undefined and the download silently fails.
 *
 * We reconstruct candidate keys from the message's own data, force-load
 * the chat into the WA store, and try each key until we find it.
 *
 * @param {object} client - The whatsapp-web.js Client instance.
 * @param {object} message - A whatsapp-web.js Message object.
 * @param {object} [options]
 * @param {number} [options.retries=5]
 * @param {number} [options.delayMs=400]
 * @returns {Promise<{data: string, mimetype: string, filename: string|null}|{error: string}|null>}
 */
export async function downloadMediaFixed(
  client,
  message,
  { retries = 5, delayMs = 400 } = {},
) {
  if (!message.hasMedia) return null;
  if (!client.pupPage) {
    console.log("[Bridge] pupPage not ready");
    return null;
  }

  // Force WhatsApp Web to load this chat's messages into the front-end Msg
  // collection. Without this, Msg stays empty for chats that are never
  // "opened" in a headless session — no amount of key-format guessing helps.
  try {
    const chat = await message.getChat();
    await chat.fetchMessages({ limit: 5 });
  } catch (e) {
    console.error(
      "[Bridge] Failed to pre-load chat for media lookup:",
      e.message,
    );
  }

  const msgKeys = buildMsgKeys(message);
  if (msgKeys.length === 0) {
    console.log(
      "[Bridge] Could not build message keys, falling back to original downloadMedia",
    );
    return message.downloadMedia();
  }

  for (let attempt = 1; attempt <= retries; attempt++) {
    const result = await client.pupPage.evaluate(async (msgKeys) => {
      let msg = null;
      for (const key of msgKeys) {
        msg =
          window.require("WAWebCollections").Msg.get(key) ||
          (await window.require("WAWebCollections").Msg.getMessagesById([key]))
            ?.messages?.[0];
        if (msg) break;
      }

      if (!msg) return { error: "not_found" };

      if (!msg.mediaData || msg.mediaData.mediaStage === "REUPLOADING") {
        return { error: "media_unavailable", stage: msg.mediaData?.mediaStage };
      }

      if (msg.mediaData.mediaStage !== "RESOLVED") {
        try {
          await msg.downloadMedia({
            downloadEvenIfExpensive: true,
            rmrReason: 1,
          });
        } catch (e) {
          return { error: "resolve_failed", stage: msg.mediaData.mediaStage };
        }
      }

      if (
        msg.mediaData.mediaStage.includes("ERROR") ||
        msg.mediaData.mediaStage === "FETCHING"
      ) {
        return { error: "bad_stage", stage: msg.mediaData.mediaStage };
      }

      try {
        const mockQpl = {
          addAnnotations: function () {
            return this;
          },
          addPoint: function () {
            return this;
          },
        };
        const decryptedMedia = await window
          .require("WAWebDownloadManager")
          .downloadManager.downloadAndMaybeDecrypt({
            directPath: msg.directPath,
            encFilehash: msg.encFilehash,
            filehash: msg.filehash,
            mediaKey: msg.mediaKey,
            mediaKeyTimestamp: msg.mediaKeyTimestamp,
            type: msg.type,
            signal: new AbortController().signal,
            downloadQpl: mockQpl,
          });

        const data =
          await window.WWebJS.arrayBufferToBase64Async(decryptedMedia);

        return {
          data,
          mimetype: msg.mimetype,
          filename: msg.filename,
        };
      } catch (e) {
        return { error: "decrypt_failed", message: e.message };
      }
    }, msgKeys);

    if (!result?.error || result.error !== "not_found") {
      return result;
    }

    console.log(
      `[Bridge] Message not yet in store, retry ${attempt}/${retries} (fromMe: ${message.fromMe})`,
    );
    if (attempt < retries) {
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }

  console.error(
    "[Bridge] Message never appeared in store after retries:",
    msgKeys[0],
  );
  return { error: "not_found_after_retries", tried: msgKeys };
}
