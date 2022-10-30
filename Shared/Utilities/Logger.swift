// Logger.swift

import Foundation
import os.log

struct Logger {
    private let logger: os.Logger
    private let label: String

    enum LogLevel {
        case info, warning, error, critical
    }

    init(label: String) {
        self.logger = os.Logger(subsystem: "BetterTG", category: label)
        self.label = label
    }

    func log(_ message: String, level: LogLevel = .info) {
        let date = Date.now.formatted(date: .omitted, time: .standard)
        switch level {
            case .info:
                logger.info("[\(date)] [\(label)] [info] \(message)")
            case .error:
                logger.error("[\(date)] [\(label)] [error] \(message)")
            case .critical:
                logger.critical("[\(date)] [\(label)] [critical] \(message)")
            case .warning:
                logger.warning("[\(date)] [\(label)] [warning] \(message)")
        }
    }
}
