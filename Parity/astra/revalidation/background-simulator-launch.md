# Background Simulator launch — 2026-10-02

- User requested no focus stealing during repeated smoke. `05d4416` changes the wrapper to `open -g -a Simulator` and syncs
  AGENTS/CLAUDE. macOS `open --help` defines `-g` as no foreground activation. Boot readiness, install, app launch and idb remain
  unchanged; no Simulator shutdown or extra activation. Shell syntax and `build-Debug-20261002-215832-37840-40.log` pass (5s,
  zero warnings); subsequent video-note/animation/gallery smoke launches succeed through this path. On the inline-animation run,
  read-only `lsappinfo front` reports the same opaque front-application ID before and after launch; no application was activated separately.
