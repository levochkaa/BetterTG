// FFmpegCapabilities.swift

import FFmpegBridge
import Foundation

enum FFmpegCapabilities {
    static var version: String {
        String(cString: BetterTGFFmpegVersion())
    }

    static var supportsVP9: Bool {
        BetterTGFFmpegHasVP9Decoder() != 0
    }

    static var supportsOpus: Bool {
        BetterTGFFmpegHasOpusDecoder() != 0
    }

    static var supportsOpusEncoding: Bool {
        BetterTGFFmpegHasOpusEncoder() != 0
    }

    static var supportsOggMuxing: Bool {
        BetterTGFFmpegHasOggMuxer() != 0
    }

    static var supportsGIF: Bool {
        BetterTGFFmpegHasGIFDecoder() != 0
    }

    static func assertRequiredCodecsAvailable() {
        #if DEBUG
            assert(supportsVP9, "FFmpeg \(version) is missing the VP9 decoder")
            assert(supportsOpus, "FFmpeg \(version) is missing the Opus decoder")
            assert(supportsOpusEncoding, "FFmpeg \(version) is missing the Opus encoder")
            assert(supportsOggMuxing, "FFmpeg \(version) is missing the Ogg muxer")
            assert(supportsGIF, "FFmpeg \(version) is missing the GIF decoder")
        #endif
    }
}
