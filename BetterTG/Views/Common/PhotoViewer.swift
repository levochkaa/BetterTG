// PhotoViewer.swift

import SwiftUI
import TDLibKit

struct PhotoViewer: View {
    
    @Binding var photoInfo: OpenedPhotoInfo?
    var namespace: Namespace.ID
    
    @State var backgroundOpacity: Double = 1
    @State var position: CGSize = .zero
    @State var scale: CGFloat = 1
    
    var dismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                position = value.translation
                let height = abs(Double(value.translation.height))
                backgroundOpacity = 1 - (height / 200)
            }
            .onEnded { value in
                withAnimation {
                    if abs(value.translation.height) > 200 {
                        photoInfo = nil
                    } else {
                        position = .zero
                        backgroundOpacity = 1
                    }
                }
            }
            .simultaneously(with: MagnificationGesture()
                .onChanged { value in
                    scale = value
                }
                .onEnded { value in
                    withAnimation {
                        if value > 1.5 {
                            scale = 1.5
                        } else if value < 1 {
                            scale = 1
                        } else {
                            scale = value
                        }
                    }
                }
            )
    }
    
    var body: some View {
        if let photoInfo,
            let photo = photoInfo.openedPhoto,
            let photoMessageId = photoInfo.openedPhotoMessageId {
            ZStack {
                Color.black
                    .ignoresSafeArea()
                    .opacity(backgroundOpacity)
                    .onTapGesture {
                        withAnimation {
                            self.photoInfo = nil
                        }
                    }
                
                photo
                    .resizable()
                    .scaledToFit()
                    .matchedGeometryEffect(id: "\(photoMessageId)", in: namespace, properties: .frame)
                    .offset(y: position.height)
                    .scaleEffect(scale)
            }
            .gesture(dismissGesture)
        }
    }
}
