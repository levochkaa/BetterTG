# Forward comment/draft slice

- **P0 flow:** pre-Liquid/current forward destination comment state, adapted to the existing UIKit multi-recipient/topic picker and
  TDLib `sendMessage(InputMessageText)` followed by `forwardMessages`.
- Implemented: expanding formatted Add a comment field retained across topic drill-down/search/retry; keyboard-layout-guide attachment
  with interactive dismissal and safe-area toolbar switching; Dynamic Type height refresh; comment snapshot at delivery start; exact
  basic-message/private/paid/forum/closed/admin eligibility; account/client checks immediately before mutation; exact returned topic.
  Each destination records the delivered `FormattedText`, so a failed forward retries without duplicating an unchanged successful
  comment, while an edited comment is a new intent. Comment failure blocks that destination's forward; ambiguous/partial forwarding keeps
  the existing nonretry policy, and controls re-enable with the comment intact.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-102642-93175-2531.log`; focused source/delta review clean. PID `93577`
  reached the real message context menu, but idb omitted its Forward overlay action, so safe navigation to the comment field was blocked.
  Evidence: `.build/ui-probe-evidence/forward-comment-final-*`; no comment or forward mutation occurred.
