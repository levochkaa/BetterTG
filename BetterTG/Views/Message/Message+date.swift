// Message+date.swift

import SwiftUI
import SwiftUIX

extension MessageView {
    @ViewBuilder var messageDate: some View {
        Text(formatted(customMessage.message.date))
            .font(.caption)
            .foregroundColor(.white).opacity(0.5)
    }
    
    @ViewBuilder var messageOverlayDate: some View {
        messageDate
            .padding(3)
            .background(.gray6)
            .cornerRadius(15)
            .padding(5)
            .menuOnPress { menu }
    }
    
    func formatted(_ time: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(time))
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        return dateFormatter.string(from: date)
    }
}
