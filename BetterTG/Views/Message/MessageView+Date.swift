// Message+date.swift

import SwiftUI

extension MessageView {
    @ViewBuilder var messageDate: some View {
        Text(formatted(customMessage.message.date))
            .font(.caption)
            .foregroundColor(.white).opacity(0.5)
    }
    
    func formatted(_ time: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(time))
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        return dateFormatter.string(from: date)
    }
}
