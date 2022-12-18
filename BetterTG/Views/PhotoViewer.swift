// PhotoViewer.swift

import SwiftUI
import TDLibKit

struct PhotoViewer: View {
    
    @Binding var photoInfo: OpenedPhotoInfo?
    var namespace: Namespace.ID
    
    @State var backgroundOpacity: Double = 1
    @State var position: CGSize = .zero
    
    let logger = Logger(label: "PhotoPreviewer")
    
    var gesture: some Gesture {
        DragGesture()
            .onChanged { value in
                position = value.translation
                let height = abs(Double(value.translation.height))
                let width = abs(Double(value.translation.width))
                if height > width {
                    backgroundOpacity = 1 - (height / 200)
                } else {
                    backgroundOpacity = 1 - (width / 100)
                }
            }
            .onEnded { value in
                withAnimation {
                    if abs(value.translation.height) > 200 || abs(value.translation.width) > 100 {
                        photoInfo = nil
                    } else {
                        position = .zero
                        backgroundOpacity = 1
                    }
                }
            }
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
                        self.photoInfo = nil
                    }
                
                photo
                    .resizable()
                    .scaledToFit()
                    .matchedGeometryEffect(id: "\(photoMessageId)", in: namespace, properties: .frame)
                    .offset(x: position.width, y: position.height)
                    .gesture(gesture)
            }
        }
    }
}
