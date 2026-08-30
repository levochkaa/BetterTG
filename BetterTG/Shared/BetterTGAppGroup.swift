// BetterTGAppGroup.swift

import Foundation

enum BetterTGAppGroup {
    static let identifier = "group.com.levochkaaa.BetterTG"

    static func containerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}
