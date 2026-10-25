# Gallery controls, keyboard navigation, and forwarding follow-up (2026-09-06)

Gallery transitions keep the media snapshot separate from the surrounding controls, including the
Live Photo button. Controls fade with drag distance and animate back during cancellation; presentation
also fades them in. Native sharing expands from the Share button. Navigation highlights the exact
media item within an album, while text messages retain a bubble highlight.

Reply controls receive their first tap while the composer is focused. Programmatic scrolling resolves
the destination again after self-sizing rows settle, then highlights it. History moves with the
composer even when reading older messages: a simulator check measured the same two messages moving
up by 301 pt and returning to their exact initial positions when the keyboard closed. Editing ends
before opening a gallery so cancelling its dismissal cannot restore the keyboard above the photo.
The gallery retains hardware shortcuts with an empty software input view, preventing the More menu
from restoring an unwanted keyboard.

The Forward picker uses the account's folders, loads each TDLib chat list before enumerating it,
keeps custom-folder searches scoped, and excludes recipients and forum topics the user cannot post to.
Selections persist across folders. Its UIKit layout has fixed search, measured folder tabs with an
underline, message previews, compact selection controls, an inset comment field, and a filled action.

Recordings and screenshots are under `.build/ui-probe-evidence/gallery-polish-20260906/` and
`.build/ui-probe-evidence/keyboard-forward-20260906/`. The latter's `18-focused-cancel.mp4` verifies
that the keyboard does not return over the gallery. The More-menu check is
`.build/ui-probe-evidence/gallery-menu-20260906/04-menu.png`; the final picker screenshots are in
`keyboard-forward-20260906/forward-final/`. Checks did not send messages. The final simulator
build `build-Debug-20260906-180319-54637-12556.log` passed without warnings. The paired iPhone became
unavailable before delivery of the final keyboard and picker changes.
