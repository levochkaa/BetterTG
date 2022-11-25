// SystemUtils.swift

import Foundation
import Combine
#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

public enum SystemUtils {
    #if os(iOS)
    public static let osVersion = UIDevice.current.systemVersion
    public static var size = UIScreen.main.bounds.size
    #elseif os(watchOS)
    public static let osVersion = WKInterfaceDevice.current().systemVersion
    public static var size = WKInterfaceDevice.current().screenBounds
    #endif

    static let logger = Logger(label: "SystemUtils")

    // swiftlint:disable force_cast
    public static func info<T>(key: String) -> T {
        Bundle.main.infoDictionary?[key]! as! T
    }

    private static func getWatchModel() -> String {
        var size: size_t = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(
            cString: &machine,
            encoding: String.Encoding.utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // swiftlint:disable function_body_length cyclomatic_complexity
    private static func getWatchName() -> String {
        let model = getWatchModel()
        logger.log("Watch model: \(model)")
        switch model {
            case "Watch1,1":
                return "Apple Watch Series 0 38mm"
            case "Watch1,2":
                return"Apple Watch Series 0 42mm"
            case "Watch2,3":
                return "Apple Watch Series 2 38mm"
            case "Watch2,4":
                return "Apple Watch Series 2 42mmm"
            case "Watch2,6":
                return "Apple Watch Series 1 38mm"
            case "Watch2,7":
                return "Apple Watch Series 1 42mm"
            case "Watch3,1":
                return "Apple Watch Series 3 38mm Cellular"
            case "Watch3,2":
                return "Apple Watch Series 3 42mm Cellular"
            case "Watch3,3":
                return "Apple Watch Series 3 38mm"
            case "Watch3,4":
                return "Apple Watch Series 3 42mm"
            case "Watch4,1":
                return "Apple Watch Series 4 40mm"
            case "Watch4,2":
                return "Apple Watch Series 4 44mm"
            case "Watch4,3":
                return "Apple Watch Series 4 40mm Cellular"
            case "Watch4,4":
                return "Apple Watch Series 4 44mm Cellular"
            case "Watch5,1":
                return "Apple Watch Series 5 40mm"
            case "Watch5,2":
                return "Apple Watch Series 5 44mm"
            case "Watch5,3":
                return "Apple Watch Series 5 40mm Cellular"
            case "Watch5,4":
                return "Apple Watch Series 5 44mm Cellular"
            case "Watch5,9":
                return "Apple Watch SE 40mm"
            case "Watch5,10":
                return "Apple Watch SE 44mm"
            case "Watch5,11":
                return "Apple Watch SE 40mm Cellular"
            case "Watch5,12":
                return "Apple Watch SE 44mm Cellular"
            case "Watch6,1":
                return "Apple Watch Series 6 40mm"
            case "Watch6,2":
                return "Apple Watch Series 6 44mm"
            case "Watch6.3":
                return "Apple Watch Series 6 40mm Cellular"
            case "Watch6,4":
                return "Apple Watch Series 6 44mm Cellular"
            case "Watch6,6":
                return "Apple Watch Series 7 41mm"
            case "Watch6,7":
                return "Apple Watch Series 7 45mm"
            case "Watch6,8":
                return "Apple Watch Series 7 41mm Cellular"
            case "Watch6,9":
                return "Apple Watch Series 7 45mm Cellular"
            case "x86_64", "arm64":
                return "Apple Watch Simulator"
            default:
                return "Unknown"
        }
    }

    public static func getDeviceModel() async -> String {
        #if os(iOS)
//        var systemInfo = utsname()
//        uname(&systemInfo)
//        return withUnsafePointer(to: &systemInfo.machine) {
//            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
//                String(validatingUTF8: $0)
//            }
//        } ?? "Unknown"
        return await UIDevice.current.name
        #elseif os(watchOS)
        return getWatchName()
        #endif
    }
}
