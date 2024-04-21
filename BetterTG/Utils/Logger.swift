// Logger.swift

import SwiftUI
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
    logger.log("[Log] [\(date, privacy: .public)] \(output, privacy: .public)")
}
