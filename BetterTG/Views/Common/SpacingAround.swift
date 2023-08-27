// SpacingAround.swift

struct SpacingAround<Content: View>: View {
    
    @State var axis: Axis?
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        if let axis {
            switch axis {
                case .horizontal:
                    HStack {
                        Spacer()
                        
                        content()
                        
                        Spacer()
                    }
                case .vertical:
                    VStack {
                        Spacer()
                        
                        content()
                        
                        Spacer()
                    }
            }
        } else {
            Group {
                Spacer()
                
                content()
                
                Spacer()
            }
        }
    }
}
