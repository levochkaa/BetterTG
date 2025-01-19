// ChatViewAlbum.swift

import SwiftUI
import TDLibKit

struct ChatViewAlbum: View {
    @State var album: [Message]
    @State var selection: Int64
    
    @State private var photos = [Int: String]()
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $selection) {
                    ForEach(album) { albumMessage in
                        if case .messagePhoto(let messagePhoto) = albumMessage.content {
                            ZoomableContainer {
                                makeMessagePhoto(from: messagePhoto)
                            }
                            .tag(albumMessage.id)
                        }
                    }
                }
                .tabViewStyle(.page)
                
                toolbar
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .padding(.bottom, UIApplication.safeAreaInsets.bottom)
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .top) { Divider() }
            }
            .ignoresSafeArea()
        }
    }
    
    var toolbar: some View {
        HStack {
            Button(systemImage: "xmark.circle.fill") {
                dismiss()
            }
            
            Spacer()
            
            if let albumMessage = album.first(where: { $0.id == selection }),
               case .messagePhoto(let messagePhoto) = albumMessage.content,
               let size = messagePhoto.photo.sizes.getSize(.yBox),
               let path = photos[size.photo.id],
               FileManager.default.fileExists(atPath: path) {
                Button(systemImage: "square.and.arrow.up.circle.fill") {
                    showShareSheet([URL(filePath: path)])
                }
            }
        }
        .font(.title)
        .foregroundStyle(.white)
    }
    
    @ViewBuilder func makeMessagePhoto(from messagePhoto: MessagePhoto) -> some View {
        TdImage(photo: messagePhoto.photo, size: .yBox, contentMode: .fit) { size, file in
            withAnimation { photos[size.photo.id] = file.local.path }
        }
    }
}
