// FFmpegVODUnknownDurationProbeFixture.swift

#if DEBUG
    import Foundation

    /// Keeps the real 12-second VP9 / 10.012-second Opus packets, but omits the
    /// video's duration tag and underestimates the container duration at 8 s.
    enum FFmpegVODUnknownDurationProbeFixture {
        static let sha256 = "70bac138704d8755b00e8c8cf05f090e21c29dae79efd69d35a3c52faec08d52"

        static func write(to url: URL) throws {
            try FFmpegVODUnequalTracksProbeFixture.write(to: url)
            var data = try Data(contentsOf: url)
            let videoTag = Data("DURATION".utf8)
            let containerDuration = Data([0x44, 0x89, 0x88, 0x40, 0xC7, 0x70, 0, 0, 0, 0, 0])
            guard let videoRange = data.range(of: videoTag),
                  let durationRange = data.range(of: containerDuration)
            else { throw CocoaError(.fileReadCorruptFile) }
            // Equal-sized substitutions preserve EBML sizes, packet offsets and cues.
            data.replaceSubrange(videoRange, with: Data("XURATION".utf8))
            data.replaceSubrange(durationRange, with: [0x44, 0x89, 0x88, 0x40, 0xBF, 0x40, 0, 0, 0, 0, 0])
            try data.write(to: url, options: .atomic)
        }
    }
#endif
