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
    
    static let modelName: String = {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        // swiftlint:disable cyclomatic_complexity
        func mapToDevice(identifier: String) -> String {
            switch identifier {
                case "iPhone10,1", "iPhone10,4": return "iPhone 8"
                case "iPhone10,2", "iPhone10,5": return "iPhone 8 Plus"
                case "iPhone10,3", "iPhone10,6": return "iPhone X"
                case "iPhone11,2": return "iPhone XS"
                case "iPhone11,4", "iPhone11,6": return "iPhone XS Max"
                case "iPhone11,8": return "iPhone XR"
                case "iPhone12,1": return "iPhone 11"
                case "iPhone12,3": return "iPhone 11 Pro"
                case "iPhone12,5": return "iPhone 11 Pro Max"
                case "iPhone13,1": return "iPhone 12 mini"
                case "iPhone13,2": return "iPhone 12"
                case "iPhone13,3": return "iPhone 12 Pro"
                case "iPhone13,4": return "iPhone 12 Pro Max"
                case "iPhone14,4": return "iPhone 13 mini"
                case "iPhone14,5": return "iPhone 13"
                case "iPhone14,2": return "iPhone 13 Pro"
                case "iPhone14,3": return "iPhone 13 Pro Max"
                case "iPhone14,7": return "iPhone 14"
                case "iPhone14,8": return "iPhone 14 Plus"
                case "iPhone15,2": return "iPhone 14 Pro"
                case "iPhone15,3": return "iPhone 14 Pro Max"
                case "iPhone8,4":  return "iPhone SE"
                case "iPhone12,8": return "iPhone SE (2nd generation)"
                case "iPhone14,6": return "iPhone SE (3rd generation)"
                case "Watch4,1", "Watch4,2", "Watch4,3", "Watch4,4": return "Apple Watch Series 4"
                case "Watch5,1", "Watch5,2", "Watch5,3", "Watch5,4": return "Apple Watch Series 5"
                case "Watch5,9", "Watch5,10", "Watch5,11", "Watch5,12": return "Apple Watch SE"
                case "Watch6,1", "Watch6,2", "Watch6,3", "Watch6,4": return "Apple Watch Series 6"
                case "Watch6,6", "Watch6,7", "Watch6,8", "Watch6,9": return "Apple Watch Series 7"
                case "Watch6,10", "Watch6,11", "Watch6,12", "Watch6,13": return "Apple Watch SE (2nd generation)"
                case "Watch6,14", "Watch6,15", "Watch6,16", "Watch6,17": return "Apple Watch Series 8"
                case "Watch6,18": return "Apple Watch Ultra"
                case "i386", "x86_64", "arm64":
                    #if os(iOS)
                    let id = ProcessInfo().environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "iOS"
                    #elseif os(watchOS)
                    let id = ProcessInfo().environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "watchOS"
                    #endif
                    let device = mapToDevice(identifier: id)
                    return "Simulator \(device)"
                default: return identifier
            }
        }
        
        return mapToDevice(identifier: identifier)
    }()
    
    static let logger = Logger(label: "SystemUtils")
    
    // swiftlint:disable force_cast
    public static func info<T>(key: String) -> T {
        Bundle.main.infoDictionary?[key]! as! T
    }
}
