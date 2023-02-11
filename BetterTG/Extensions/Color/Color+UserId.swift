// userId.swift

import SwiftUI

extension Color {
    init(fromUserId userId: Int64) {
        let colors: [Color] = [
            .red,
            .green,
            .yellow,
            .blue,
            .purple,
            .pink,
            .blue,
            .orange
        ]
        let id = Int(String(userId).replacing("-100", with: "")) ?? 0
        self.init(uiColor: UIColor(colors[[0, 7, 4, 1, 6, 3, 5][id % 7]]))
    }
}
