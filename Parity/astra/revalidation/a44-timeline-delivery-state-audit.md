# A44 timeline delivery-state audit — 2026-10-03

- Source baseline `ddfa897`, independently confirmed: `MessageView.swift`514–551 builds text, standalone and media-overlay
  timestamps with only `sendFailed`; AX576 reuses that value. `CustomMessage` has no derived read state. A43 updates list
  rows only: bubbles do not consume that watermark. `ChatVM+Publishers.swift`13–16 observes inbox but no outbox;122–129
  refreshes only the explicit route topic and discards direct scalar topic receipt updates in all-messages mode.
- Narrow repair must preserve raw sending-state precedence before comparing a temporary message ID to read watermarks;
  accepted final/failure replacement cannot keep a stale temporary state. Use current-client chat watermark for ordinary
  messages and exact per-message forum-topic watermark in both explicit-topic and all-messages routes. Missing topic state
  cannot fall back to another topic or the global chat. Late getChat/getForumTopic must not overwrite intervening accepted
  receipt updates. Do not carry old-client receipt authority through restoration seeds.
- Existing `ChatView.messagesDidChange` updates structural snapshots but reconfigures only headers (1769–1781), and its
  VM object observer updates chrome/composer. A watermark field alone will not refresh settled bubbles. Use targeted stable
  `DisplayedMessageID` reconfiguration through the existing anchor-preserving path, with no new scroll intent. BetterTG's
  album representative is newest-first (`ChatVM.swift`3578–3605), whereas Telegram's message/read status comes from its
  canonical first item; select that status source explicitly and recompute after replacement/deletion/promotion.
- References: current `6ad963e5b62d354da79040f388ae2b9132fb17b8` / pre-Liquid
  `8e7e5fefb1b0aba8335d8c28b62138183d61dc3d`, `TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/`
  `ChatMessageTextBubbleContentNode.swift`337–346 /360–369 uses Failed → Sending → Sent(read).
  Current `ChatMessageDateAndStatusNode/Sources/ChatMessageDateAndStatusNode.swift`32–44,607–683 supplies outgoing clock/
  single/double check variants; `ChatMessageItemImpl/Sources/ChatMessageItemImpl.swift`255–269 /235–249 selects grouped status.
  `TelegramCore/Sources/Utils/MessageUtils.swift`348–378 /351–380 defines effective direction, including self and broadcast.
- TDLib `022d6020`, `MessagesManager.cpp`32931–32934 gives broadcast channels a maximal outbox watermark, not a personal
  read receipt.11567–11576 marks ordinary self messages non-outgoing. Do not mechanically show Read on broadcast posts or
  hide pending/failure in Saved Messages. Final self-check styling requires an explicit reference mapping; do not invent it.
  `updateForumTopic` carries its own watermark. Optional `updateMessageSendAcknowledged` (`td_api.tl`10300–10304) only means
  quick acknowledgement, may precede failure and is not final success/read. Fullscreen gallery controls are outside this
  status repair; bubble media overlays are in scope. Source audit only; no new production code or live message send/read proof.
