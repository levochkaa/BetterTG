// FFmpegVODUnknownDurationProbeFixture.swift

#if DEBUG
    import Foundation

    /// Keeps the real 12-second VP9 / 10.012-second Opus packets, but omits the
    /// video's duration tag and supplies an inaccurate container estimate.
    enum FFmpegVODUnknownDurationProbeFixture {
        static let sha256 = "70bac138704d8755b00e8c8cf05f090e21c29dae79efd69d35a3c52faec08d52"
        static let overestimatedSHA256 = "4108eff856e12cf7c1192b30834848e6908a7066eaaef8d2da608930fbe4c002"

        static func write(to url: URL, estimatedDuration: TimeInterval = 8) throws {
            try FFmpegVODUnequalTracksProbeFixture.write(to: url)
            var data = try Data(contentsOf: url)
            let videoTag = Data("DURATION".utf8)
            let containerDuration = Data([0x44, 0x89, 0x88, 0x40, 0xC7, 0x70, 0, 0, 0, 0, 0])
            guard let videoRange = data.range(of: videoTag),
                  let durationRange = data.range(of: containerDuration)
            else { throw CocoaError(.fileReadCorruptFile) }
            // Equal-sized substitutions preserve EBML sizes, packet offsets and cues.
            data.replaceSubrange(videoRange, with: Data("XURATION".utf8))
            var durationBits = (estimatedDuration * 1000).bitPattern.bigEndian
            var replacement = Data([0x44, 0x89, 0x88])
            withUnsafeBytes(of: &durationBits) { replacement.append(contentsOf: $0) }
            data.replaceSubrange(durationRange, with: replacement)
            try data.write(to: url, options: .atomic)
        }
    }
#endif
