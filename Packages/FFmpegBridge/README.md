# FFmpegBridge

This local package exposes the narrow libav C surface used by BetterTG. The binary target is pinned to the
`FFmpeg-9.0` release from `flocked/ffmpeg-apple-xcframeworks` and its SwiftPM checksum.

The upstream build uses `--disable-autodetect`, enables the standard FFmpeg libraries plus Apple
AudioToolbox/VideoToolbox integrations, and does not enable GPL or nonfree components. FFmpeg remains licensed by
the FFmpeg project; the wrapper source in this directory is part of BetterTG.
