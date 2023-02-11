// ItemsPreview.swift

import SwiftUI
import TDLibKit

struct ItemsPreview: View {
    
    @State var offset: CGFloat = 0
    @State var opacity: Double = 1
    
    @EnvironmentObject var viewModel: RootViewModel
    
    var body: some View {
        ZoomableScrollView {
            if let openedItems = viewModel.openedItems {
                openedItems.image
                    .resizable()
                    .scaledToFit()
                    .offset(y: offset)
            }
        }
        .ignoresSafeArea()
        .if(viewModel.openedItems != nil) {
            $0.matchedGeometryEffect(id: "\(viewModel.openedItems!.id)", in: viewModel.namespace, properties: .frame)
        }
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    offset = value.translation.height
                    opacity = 1 - abs(Double(value.translation.height)) / 200
                }
                .onEnded { value in
                    withAnimation {
                        if abs(value.translation.height) > 200 {
                            viewModel.openedItems = nil
                            opacity = 0
                        } else {
                            offset = 0
                            opacity = 1
                        }
                    }
                }
        )
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(opacity)
                .frame(maxHeight: .infinity)
                .ignoresSafeArea()
                .scaledToFill()
                .onTapGesture {
                    withAnimation {
                        viewModel.openedItems = nil
                    }
                }
        }
        .zIndex(1)
    }
}
