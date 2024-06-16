// Utils.swift

import SwiftUI

enum Utils {
    static var maxMessageContentWidth = UIScreen.main.bounds.width * 0.8 - 32
    static let applicationVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    
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
            case "iPhone12,8": identifier = "iPhone SE (2nd)"
            case "iPhone14,6": identifier = "iPhone SE (3rd)"
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
            case "iPhone15,4": identifier = "iPhone 15"
            case "iPhone15,5": identifier = "iPhone 15 Plus"
            case "iPhone16,1": identifier = "iPhone 15 Pro"
            case "iPhone16,2": identifier = "iPhone 15 Pro Max"
            default: break
        }
        
        return simulator ? "Simulator \(identifier)" : identifier
    }()
}
