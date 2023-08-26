// Logger.swift

import Foundation
import os.log

let logger = os.Logger(subsystem: "BetterTG", category: "BetterTG")
let dateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "HH:mm:ss"
    return dateFormatter
}()

func log(_ messages: Any...) {
    let date = dateFormatter.string(from: Date.now)
    let output = messages.map { "\($0)" }.joined(separator: "\n")
    logger.log("[\(date, privacy: .public)] \(output, privacy: .public)")
}
