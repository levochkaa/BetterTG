// Logger.swift

import Foundation
import os.log

// swiftlint:disable line_length
func log(_ messages: Any..., file: String = #fileID, function: String = #function, line: Int = #line) {
    // actually impossible cases
    guard let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String else {
        return print("Unable to get App Name")
    }
    guard let projectName = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String else {
        return print("Unable to get Project Name")
    }
    guard let fileName = file.split(separator: "/").last?.split(separator: ".").first else {
        return print("Unable to get fileName info for \(file), with \(messages)")
    }
    
    let logger = os.Logger(subsystem: appName, category: projectName)
    
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "HH:mm:ss"
    let date = dateFormatter.string(from: Date.now)
    
    var output = messages.map { "\($0)" }.joined(separator: ";\n")
    
    #if DEBUG
    // privacy: .public - to see logs in Console.app, when running on a real device
    logger.log("[\(date, privacy: .public)] [\(fileName, privacy: .public)] [\(function, privacy: .public)] [\(line, privacy: .public)]\n\(output, privacy: .public)")
    #else
    logger.log("[\(date)] [\(fileName)] [\(function)] [\(line)]\n\(output)")
    #endif
}
