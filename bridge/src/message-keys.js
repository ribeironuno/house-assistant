/**
 * Builds candidate WhatsApp message store keys for a message.
 *
 * whatsapp-web.js v1.34.7 has a bug where getMessageModel strips the
 * `_serialized` prototype getter from the MsgKey via Object.assign, so
 * we try several known serialization layouts until the store lookup hits.
 *
 * Known layouts (varies by WA Web version / LID vs PN addressing):
 *   `{remote}_{participant}_{id}`
 *   `{remote}_{participant}_{out|in}_{id}`
 *   `{remote}_{out|in}_{participant}_{id}`
 *   `{remote}_{id}`
 *   `{remote}_{out|in}_{id}`
 *
 * @param {object} msg - A whatsapp-web.js Message object.
 * @returns {string[]}
 */
export function buildMsgKeys(msg) {
  const remote = msg.id?.remote;
  const id = msg.id?.id;
  if (!remote || !id) return [];
  const dir = msg.id?.fromMe ? "out" : "in";
  const participant = msg.id?.participant || msg.author;
  const keys = [`${remote}_${id}`, `${remote}_${dir}_${id}`];
  if (participant) {
    keys.push(
      `${remote}_${participant}_${id}`,
      `${remote}_${participant}_${dir}_${id}`,
      `${remote}_${dir}_${participant}_${id}`,
    );
  }
  return keys;
}
