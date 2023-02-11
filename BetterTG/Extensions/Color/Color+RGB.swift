// Color+RGB.swift

import SwiftUI

extension Color {
    init(red: Int, green: Int, blue: Int, opacity: Double) {
        self.init(.sRGB, red: Double(red/255), green: Double(green/255), blue: Double(blue/255), opacity: opacity)
    }
}
