# Contact send options — 2026-10-30

Scope: silent/scheduled contact sending, from `cc31638a` on `t3/refresh-goal-prompt`.
Implementation is in this audit's commit. Editable attachment comments remain a separate open gap.

## Reference and changes

Telegram `telegram-upstream/master`, `fb0e62ba8a147f0821da6aa63c09da7d79a10111`, read with `git show`:

- `submodules/AttachmentUI/Sources/AttachmentController.swift`: the common panel forwards ordinary,
  silent, scheduled and when-online sends to its active picker context.
- `submodules/TelegramUI/Sources/ContactSelectionController.swift`: ContactsPickerContext carries
  silent/schedule parameters to the selected contacts.
- `submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift`: the same send parameters
  survive multiple contacts, a primitive card and extended-vCard field selection.

Gallery and Contact now share AttachmentSendCapabilities and AttachmentSendTiming. Saved Messages
offers Set a Reminder without silent/online actions; destinations without scheduling offer only
silent sending. Gallery retains its caption-position section and media-timer scheduling exclusion.

Contact's shared Send row opens the existing source-morph menu with the continuing gesture. The
existing schedule picker leaves selection intact on Cancel. Send options follow the selected contacts
through the primitive and extended-card paths and reach ChatVM.sendAttachmentContents. That method
uses one options value for every contact, retaining default broadcast silent-posting behavior when
no explicit options were supplied. Existing reply/topic ownership and cleanup remain in place.

The local ContactSelectionPanelProbe now switches destination capabilities and records the exact
callback options and vCard count. Cora 08 has an injected local card with a test email, allowing the
real field selector to run without reading or changing the phonebook. Sends remain intercepted.

## Verification

SwiftFormat covered all six changed Swift files in one invocation. Final `./build.sh build` passed
in 22 s; complete log `build-Debug-20261030-015209-81115-27206.log` has zero warnings/errors.
Built and freshly resolved installed debug dylibs matched SHA-256
`f554cf089103db229951087b6c2d90a1f4d2bec6a31bd600132e5210a92d0c5b`.
`git diff --check` passed.

The first build, before extending the local vCard fixture, passed without warnings/errors:
`build-Debug-20261030-014540-53634-15045.log`, 32 s; built and installed dylibs matched SHA-256
`0052dddbcea3ed5ca50b9bdd9bffec1b6a06c8b45bc9d6ca6ba1e0dcc552f2e5`.
On iPhone 17 Pro Simulator / iOS 26.5, `8108A92F-7E93-49C8-87F4-FA53A5A40A99`, T3 Device panel:

- Regular destination showed Send Without Sound, Send When Online and Schedule Message. Cancelling
  the date picker preserved the two selected contacts and did not send.
- One continuous drag held Send for 850 ms, moved for 600 ms and held the destination for 300 ms.
  Its endpoint used the observed underlying Ada 03 label's position, inside the menu's silent row.
  The callback fired once with ordered `Ada 01,Ada 02`, `now,silent:true,id:1`; no second tap.
- Single primitive contact returned `online,silent:false,id:0`, then a separate run returned
  `date:1793310600,silent:false,id:0`.
- Reminder mode showed only Set a Reminder. Its picker omitted When Online and returned the chosen
  date. No-schedule mode showed only Send Without Sound, also checked in light appearance.
- Menu dismissal followed by double Send produced one ordinary callback, giving five sends and
  five dismissals across the completed scenarios. A tap attempted during menu dismissal was refused
  by the tool as covered by Close; fresh snapshot and the single retry succeeded.

Reduced menu screenshots and the continuous-gesture recording were inspected. Local evidence:
`/tmp/bettertg-contact-options-{initial,menu,reminder-menu,no-schedule}.png`,
`/tmp/bettertg-contact-options-drag.mp4`,
`/tmp/bettertg-contact-options-drag-frames-small.jpg`,
`/tmp/bettertg-contact-options-first-build.txt`. The recording's telemetry sidecar has no events;
the CLI's drag result records the continuous gesture and its resolved endpoints. These are local,
non-durable artifacts.

Final build on the same Simulator:

- Search selected local Cora 08 and dismissed its keyboard. Silent Send opened the real field
  selector with the local number and email selected. Double Send returned exactly one callback:
  `sends=1; dismissals=1; names=Cora 08; vcards=1; options=now,silent:true,id:1`.
  The resting snapshot omitted the visible navigation buttons, so Send used its observed screenshot
  position. This is not VoiceOver proof.
- A new picker selected Ada 01 then Ada 02 and chose When Online. Result:
  `sends=2; dismissals=2; names=Ada 01,Ada 02; vcards=0; options=online,silent:false,id:0`.
- Real Saved Messages → Gallery → select a photo → hold Send showed only Set a Reminder. The menu
  and Gallery were cancelled without sending or importing the selection into the composer.
- Normal relaunch restored Chats. No recording remains active.

Final evidence: `/tmp/bettertg-contact-options-vcard.png`,
`/tmp/bettertg-contact-options-final.txt`, `/tmp/bettertg-contact-options-gallery-bottom.png`.

## Limits and next

This proves the picker/callback path and reviews the TDLib option forwarding; no real contact was
sent or scheduled. Server delivery, errors/partial multi-contact sends, reply/topic delivery,
broadcast defaults and the existing slow-mode guard need their own runtime coverage. Gallery's
caption/timer rules were reviewed in source; only its Saved Messages reminder menu was rechecked
at runtime in this slice.

Editable rich-text attachment comments remain absent. Preserve entities and common ownership across
tab changes when adding them; Telegram sends a contact comment as a preceding text message. No account,
draft, phonebook, sticker set or preference was changed. Other menu/readiness, Stories, accessibility,
iPad/rotation/RTL, iOS 27 and physical-device gaps remain open.
