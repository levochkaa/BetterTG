# Forward recipient navigation and composer preview (2026-09-06)

The production Forward picker now reuses the main screen's bottom `FolderPickerView`,
`UIPageViewController` paging and `TelegramListNavigationBar` search. Recipient rows contain
only a 40-point avatar and title, with a 56-point minimum height. Existing account, content,
private-recipient and forum-topic eligibility filtering remains in place. The picker has no
comment field, recipient counter or send toolbar.

Selecting a chat/topic opens that destination with a cancellable `PendingMessageForward`
preview above the composer: a Forward title and sender/content summary. The composer Send
action sends any comment first, then invokes the existing forwarding service with fresh
permission checks; ambiguous partial results are not offered for automatic retry. Choosing
another reply replaces the pending forward. The old offline selection fixture's toolbar is
now private to its legacy debug probe.

Simulator evidence: `.build/ui-probe-evidence/forward-redesign-20260906/` contains the compact
picker (`05-forward.png`), horizontal paging (`06-folder-swipe.mp4`), folder tap and search,
recipient-to-composer transition (`11-recipient-to-draft.mp4`, `11-draft.png`) and cancellation
(`12-canceled.png`). These checks did not send messages. All changed Swift files were formatted;
`build-Debug-20260906-221323-59280-9033.log` records a successful build with no warnings or errors.
