// SpacingAround.swift

import SwiftUI

struct SpacingAround<Content: View>: View {
    
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        Group {
            Spacer()
            
            content()
            
            Spacer()
        }
    }
}
