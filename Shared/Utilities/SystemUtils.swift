// SystemUtils.swift

import Foundation
import UIKit

public enum SystemUtils {
    public static let osVersion = UIDevice.current.systemVersion

    // swiftlint:disable force_cast
    public static func info<T>(key: String) -> T {
        Bundle.main.infoDictionary?[key]! as! T
    }

    public static func getDeviceModel() async -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        } ?? "Unknown"
    }
}
