// CaptionText.swift

import SwiftUI

struct CaptionText: View {
    let dateString: String
    
    var body: some View {
        Text(dateString)
            .font(.caption)
            .foregroundStyle(.white).opacity(0.5)
    }
}
