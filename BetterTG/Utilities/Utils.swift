// Utils.swift

import Foundation
import Combine
import UIKit

enum Utils {
    static let osVersion = UIDevice.current.systemVersion
    static var size = UIScreen.main.bounds.size
    static let defaultAnimationDuration = 0.35
    
    static let modelName: String = {
        var simulator = false
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        var identifier = machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
        
        if ["i386", "x86_64", "arm64"].contains(identifier) {
            identifier = ProcessInfo().environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "iOS"
            simulator = true
        }
        
        switch identifier {
            case "iPhone10,1", "iPhone10,4": identifier = "iPhone 8"
            case "iPhone10,2", "iPhone10,5": identifier = "iPhone 8 Plus"
            case "iPhone10,3", "iPhone10,6": identifier = "iPhone X"
            case "iPhone11,2": identifier = "iPhone XS"
            case "iPhone11,4", "iPhone11,6": identifier = "iPhone XS Max"
            case "iPhone11,8": identifier = "iPhone XR"
            case "iPhone12,1": identifier = "iPhone 11"
            case "iPhone12,3": identifier = "iPhone 11 Pro"
            case "iPhone12,5": identifier = "iPhone 11 Pro Max"
            case "iPhone13,1": identifier = "iPhone 12 mini"
            case "iPhone13,2": identifier = "iPhone 12"
            case "iPhone13,3": identifier = "iPhone 12 Pro"
            case "iPhone13,4": identifier = "iPhone 12 Pro Max"
            case "iPhone14,4": identifier = "iPhone 13 mini"
            case "iPhone14,5": identifier = "iPhone 13"
            case "iPhone14,2": identifier = "iPhone 13 Pro"
            case "iPhone14,3": identifier = "iPhone 13 Pro Max"
            case "iPhone14,7": identifier = "iPhone 14"
            case "iPhone14,8": identifier = "iPhone 14 Plus"
            case "iPhone15,2": identifier = "iPhone 14 Pro"
            case "iPhone15,3": identifier = "iPhone 14 Pro Max"
            case "iPhone8,4":  identifier = "iPhone SE"
            case "iPhone12,8": identifier = "iPhone SE (2nd)"
            case "iPhone14,6": identifier = "iPhone SE (3rd)"
            default: break
        }
        return simulator ? "Simulator \(identifier)" : identifier
    }()
    
    // swiftlint:disable force_cast
    static func info<T>(key: String) -> T {
        Bundle.main.infoDictionary?[key]! as! T
    }
}
