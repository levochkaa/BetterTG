// ItemView.swift

import SwiftUI

struct ItemView: View {
    
    @State var item: OpenedItem
    
    @State private var offsetY: CGFloat = 0
    @State private var opacity: Double = 1
    
    @EnvironmentObject var viewModel: RootViewModel
    
    var hideGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let height = value.translation.height
                offsetY = height
                opacity = 1 - abs(Double(height)) / 200
            }
            .onEnded { value in
                withAnimation {
                    if abs(value.translation.height) > 200 {
                        viewModel.openedItem = nil
                        opacity = 0
                    } else {
                        offsetY = 0
                        opacity = 1
                    }
                }
            }
    }
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .opacity(opacity)
                .onTapGesture {
                    withAnimation {
                        viewModel.openedItem = nil
                    }
                }
            
            item.image
                .resizable()
                .scaledToFit()
                .matchedGeometryEffect(id: item.id, in: viewModel.namespace)
                .offset(y: offsetY)
                .gesture(hideGesture)
        }
    }
}
