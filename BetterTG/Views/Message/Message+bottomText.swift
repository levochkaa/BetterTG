// Message+bottomText.swift

import SwiftUI

extension MessageView {
    @ViewBuilder var bottomText: some View {
        HStack(alignment: .center, spacing: 3) {
            if !isOutgoing {
                Text(formatted(customMessage.message.date))
            }
            
            if customMessage.message.editDate != 0 {
                Text("edited")
            }
            
            if isOutgoing {
                Text(formatted(customMessage.message.date))
            }
        }
    }
    
    func formatted(_ time: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(time))
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        return dateFormatter.string(from: date)
    }
}
