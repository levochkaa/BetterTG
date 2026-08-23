// TGSDecompression.swift

import Foundation
import zlib

// MARK: - TGSDecompressionError

enum TGSDecompressionError: Swift.Error {
    case emptyInput
    case inputTooLarge
    case outputTooLarge
    case inflateFailed(Int32)
}

func decompressTGS(_ data: Data) throws -> Data {
    let maximumInputSize = 4 * 1024 * 1024
    let maximumOutputSize = 16 * 1024 * 1024
    guard !data.isEmpty else { throw TGSDecompressionError.emptyInput }
    guard data.count <= maximumInputSize else { throw TGSDecompressionError.inputTooLarge }

    if data.first == UInt8(ascii: "{") || data.first == UInt8(ascii: "[") {
        return data
    }

    var stream = z_stream()
    var status = inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
    guard status == Z_OK else { throw TGSDecompressionError.inflateFailed(status) }
    defer { inflateEnd(&stream) }

    let bufferSize = 64 * 1024
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    var output = Data()

    try data.withUnsafeBytes { inputBuffer in
        guard let input = inputBuffer.bindMemory(to: UInt8.self).baseAddress else {
            throw TGSDecompressionError.emptyInput
        }
        stream.next_in = UnsafeMutablePointer(mutating: input)
        stream.avail_in = UInt32(data.count)

        repeat {
            try Task.checkCancellation()
            try buffer.withUnsafeMutableBufferPointer { outputBuffer in
                stream.next_out = outputBuffer.baseAddress
                stream.avail_out = UInt32(bufferSize)
                status = inflate(&stream, Z_NO_FLUSH)
                guard status == Z_OK || status == Z_STREAM_END else {
                    throw TGSDecompressionError.inflateFailed(status)
                }

                let produced = bufferSize - Int(stream.avail_out)
                guard output.count + produced <= maximumOutputSize else {
                    throw TGSDecompressionError.outputTooLarge
                }
                if produced > 0, let bytes = outputBuffer.baseAddress {
                    output.append(bytes, count: produced)
                }
            }
        } while status != Z_STREAM_END
    }

    return output
}
