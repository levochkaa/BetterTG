// ContextButtonInfo.swift

import SwiftUI

struct ContextButtonInfo: Identifiable {
    var id = UUID()
    let text: LocalizedStringKey
    let systemImage: String
    let role: ButtonRole?
    let action: () -> Void
}
