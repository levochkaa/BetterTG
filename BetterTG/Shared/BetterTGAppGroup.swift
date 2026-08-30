// BetterTGAppGroup.swift

import Foundation

enum BetterTGAppGroup {
    static let identifier = "group.com.levochkaaa.BetterTG"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    static func containerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
