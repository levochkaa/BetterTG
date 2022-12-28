// Logger.swift

import Foundation
import os.log

struct Logger {
    private let logger: os.Logger
    private let label: String
    
    init(_ label: String) {
        logger = os.Logger(subsystem: "BetterTG", category: label)
        self.label = label
    }
    
    func log(_ messages: Any...) {
        let date = Date.now.formatted(date: .omitted, time: .standard)
        var output = ""
        for message in messages {
            output += "\(message) "
        }
        #if DEBUG
        // privacy: .public - to see logs in Console.app, when running on a real device
        logger.log("[\(date, privacy: .public)] [\(label, privacy: .public)] \(output, privacy: .public)")
        #else
        logger.log("[\(date)] [\(label)] \(output)")
        #endif
    }
}
