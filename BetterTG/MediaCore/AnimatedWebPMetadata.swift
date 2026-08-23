// AnimatedWebPMetadata.swift

import Foundation
import libwebp

// MARK: - AnimatedWebPMetadata

struct AnimatedWebPMetadata {
    let width: Int
    let height: Int
    let loopCount: Int
    let frameEndTimes: [TimeInterval]
}

func decodeAnimatedWebPMetadata(data: NSData) -> AnimatedWebPMetadata? {
    let maximumFrameCount = 600
    let maximumDimension = 2048
    let maximumPixelCount = 4 * 1024 * 1024

    var webPData = WebPData(
        bytes: data.bytes.assumingMemoryBound(to: UInt8.self),
        size: data.length,
    )
    guard let demuxer = WebPDemux(&webPData) else { return nil }
    defer { WebPDemuxDelete(demuxer) }

    let width = Int(WebPDemuxGetI(demuxer, WEBP_FF_CANVAS_WIDTH))
    let height = Int(WebPDemuxGetI(demuxer, WEBP_FF_CANVAS_HEIGHT))
    let frameCount = Int(WebPDemuxGetI(demuxer, WEBP_FF_FRAME_COUNT))
    guard width > 0,
          height > 0,
          width <= maximumDimension,
          height <= maximumDimension,
          width * height <= maximumPixelCount,
          frameCount > 0,
          frameCount <= maximumFrameCount
    else { return nil }

    var frameEndTimes = [TimeInterval]()
    frameEndTimes.reserveCapacity(frameCount)
    var iterator = WebPIterator()
    guard WebPDemuxGetFrame(demuxer, 1, &iterator) != 0 else { return nil }
    defer { WebPDemuxReleaseIterator(&iterator) }
    var endTime = TimeInterval.zero
    repeat {
        guard !Task.isCancelled else { return nil }
        endTime += max(0.02, Double(iterator.duration) / 1000)
        frameEndTimes.append(endTime)
    } while WebPDemuxNextFrame(&iterator) != 0
    guard frameEndTimes.count == frameCount else {
        return nil
    }

    return AnimatedWebPMetadata(
        width: width,
        height: height,
        loopCount: Int(WebPDemuxGetI(demuxer, WEBP_FF_LOOP_COUNT)),
        frameEndTimes: frameEndTimes,
    )
}

func makeAnimatedWebPDecoder(data: NSData) -> OpaquePointer? {
    var webPData = WebPData(
        bytes: data.bytes.assumingMemoryBound(to: UInt8.self),
        size: data.length,
    )
    var options = WebPAnimDecoderOptions()
    guard WebPAnimDecoderOptionsInit(&options) != 0 else { return nil }
    options.color_mode = MODE_bgrA
    options.use_threads = 1
    return WebPAnimDecoderNew(&webPData, &options)
}
