// Logger.swift

import Darwin
import Foundation
import os.log

let logger = os.Logger(subsystem: "BetterTG", category: "BetterTG")
let dateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "HH:mm:ss"
    return dateFormatter
}()

func log(_ messages: Any...) {
    let date = dateFormatter.string(from: .now)
    let output = messages.map { "\($0)" }.joined(separator: "\n")
    let line = "[Log] [\(date)] \(output)"
    logger.log("\(line, privacy: .public)")
    #if DEBUG
    fputs("[BetterTG] \(line)\n", stderr)
    fflush(stderr)
    #endif
}
