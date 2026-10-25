# Delete collapse/fade/slide slice

- **P0 flow:** Telegram-style restrained delete transition without dust/particles, integrated with authoritative TDLib
  `updateDeleteMessages` and the inverted diffable timeline.
- Implemented: ChatVM announces only bubbles whose complete source-message set disappears; visible sources become noninteractive and
  animate 140ms opacity + directional 24pt slide + 0.98 scale; the delayed heterogeneous snapshot then performs layout collapse. Rapid
  deletes coalesce to one deadline, cell reuse resets all presentation state, nonvisible deletes apply immediately, album-member survivors
  stay in place, video teardown still follows `didEndDisplaying`, and the collapse anchor is restricted to IDs surviving in canonical state.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-092113-77487-3754.log`; focused source/delta review clean. No deliberate
  server delete was performed, so visual runtime mutation proof remains deferred.
