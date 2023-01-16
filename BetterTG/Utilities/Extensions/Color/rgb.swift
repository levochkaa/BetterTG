// rgb.swift

import SwiftUI

extension Color {
    init(r: Int, g: Int, b: Int) {
        self.init(red: Double(r/255), green: Double(g/255), blue: Double(b/255))
    }
}
