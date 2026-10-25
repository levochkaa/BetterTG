# Persistent FFmpeg session slice

- **P0 flow:** retain demux/decoder/SWR state across VOD high-water expansions, matching pre-Liquid `ChunkMediaPlayerV2.swift`,
  `FFMpegMediaDataReaderV2` and `FFMpegFileReader` session-per-seek behavior through TDLib finite range reads.
- Implemented: separate exact one-shot and soft streaming APIs; one open per seek-generation; authoritative Continue horizon; full crossing
  frames; per-track emitted cursors; end-aware track completion; globally sequenced interleaved compressed-packet FIFO with hard count and
  payload/side-data/overhead footprint bounds; cumulative session metrics and per-pump safety budgets; persistent callbacks/context;
  terminal cancellation and close barrier; no repeated lookahead after session start.
- Verification: SHA-pinned two-second boundary fixture proves three uneven pumps, one open, no rollover seek, monotonic A/V, no added
  previous-end→next-start discontinuity, exact seek, persistent supersession/cancel and EOF/SWR tail. SHA-pinned sparse unequal-track
  fixture proves video 12s plus audio packets at 0…2 and 8…10s, non-EOF first horizon, full terminal audio/video, and ordered FIFO use
  (`25` packets / `24,113` bytes). The production controller proves eleven 1s DEBUG pumps on one session plus all prior playback states.
