// DividerAround.swift

import SwiftUI

struct DividerAround<Content: View>: View {
    
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        Group {
            Divider()
            
            content()
            
            Divider()
        }
    }
}
