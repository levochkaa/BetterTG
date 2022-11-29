// Logger.swift

import Foundation
import os.log

struct Logger {
    private let logger: os.Logger
    private let label: String

    init(label: String) {
        logger = os.Logger(subsystem: "BetterTG", category: label)
        self.label = label
    }

    func log(_ messages: Any...) {
        let date = Date.now.formatted(date: .omitted, time: .standard)
        var output = ""
        for message in messages {
            output += "\(message) "
        }
        logger.log("[\(date)] [\(label)] \(output)")
    }
}
