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
        self.logger = os.Logger(subsystem: label, category: label)
        self.label = label
    }

    func log(_ message: String, level: LogLevel = .info) {
        switch level {
            case .info:
                logger.info("[\(label)] [info] \(message)")
            case .error:
                logger.error("[\(label)] [error] \(message)")
            case .critical:
                logger.critical("[\(label)] [critical] \(message)")
            case .warning:
                logger.warning("[\(label)] [warning] \(message)")
        }
    }
}
