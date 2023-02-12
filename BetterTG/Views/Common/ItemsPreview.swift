// ItemsPreview.swift

import SwiftUI
import TDLibKit

struct ItemsPreview: View {
    
    @State var offsetY: CGFloat = 0
    @State var offsetX: CGFloat = 0
    @State var opacity: Double = 1
    
    @EnvironmentObject var viewModel: RootViewModel
    
    var hideGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offsetY = value.translation.height
                opacity = 1 - abs(Double(value.translation.height)) / 200
            }
            .onEnded { value in
                withAnimation {
                    if abs(value.translation.height) > 200 {
                        viewModel.openedItems = nil
                        opacity = 0
                    } else {
                        offsetY = 0
                        opacity = 1
                    }
                }
            }
    }
    
    var slideGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offsetX = value.translation.width
            }
            .onEnded { value in
                guard let openedItems = viewModel.openedItems else { return }
                withAnimation {
                    if abs(value.translation.width) > Utils.size.width / 2 - 50 {
                        if value.translation.width < 0, openedItems.index != openedItems.images.count - 1 {
                            viewModel.openedItems?.index += 1
                        } else if value.translation.width > 0, openedItems.index != 0 {
                            viewModel.openedItems?.index -= 1
                        }
                    }
                    offsetX = 0
                }
            }
    }
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(opacity)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation {
                        viewModel.openedItems = nil
                    }
                }
            
            if let openedItems = viewModel.openedItems {
                LazyHStack(alignment: .center, spacing: 0) {
                    ForEach(openedItems.images) { identifiableImage in
                        identifiableImage.image
                            .resizable()
                            .scaledToFit()
                            .ignoresSafeArea()
                            .frame(width: Utils.size.width, height: Utils.size.height)
                            .offset(y: offsetY)
                            .gesture(hideGesture)
                            .matchedGeometryEffect(id: identifiableImage.id, in: viewModel.namespace)
                    }
                }
                .frame(width: Utils.size.width, alignment: .leading)
                .offset(x: -CGFloat(openedItems.index) * Utils.size.width + offsetX)
            }
        }
        .simultaneousGesture(slideGesture)
    }
}
