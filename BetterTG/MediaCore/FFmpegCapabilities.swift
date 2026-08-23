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

    static func assertRequiredDecodersAvailable() {
        #if DEBUG
            assert(supportsVP9, "FFmpeg \(version) is missing the VP9 decoder")
            assert(supportsOpus, "FFmpeg \(version) is missing the Opus decoder")
        #endif
    }
}
