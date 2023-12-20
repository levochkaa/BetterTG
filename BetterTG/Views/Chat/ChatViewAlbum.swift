// ChatViewAlbum.swift

import SwiftUI
import TDLibKit

struct ChatViewAlbum: View {
    @State var album: [Message]
    @State var selection: Int64
    
    @State private var shareUrl: URL?
    @State private var photos = [Int: String]()
    
    @Environment(\.safeAreaInsets) var safeAreaInsets
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
                    .padding(.bottom, safeAreaInsets.bottom)
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .top) { Divider() }
            }
            .ignoresSafeArea()
            .sheet(item: $shareUrl) { url in
                ShareSheet(items: [url])
                    .presentationDetents([.medium])
                    .ignoresSafeArea()
            }
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
                    shareUrl = URL(filePath: path)
                }
            }
        }
        .font(.title)
        .foregroundStyle(.white)
    }
    
    @ViewBuilder func makeMessagePhoto(from messagePhoto: MessagePhoto) -> some View {
        if let size = messagePhoto.photo.sizes.getSize(.yBox) {
            AsyncTdFile(id: size.photo.id) { file in
                Image(file: file)
                    .resizable()
                    .scaledToFit()
                    .onAppear { photos[size.photo.id] = file.local.path }
            } placeholder: {
                makeMessagePhotoPlaceholder(from: messagePhoto)
            }
        } else {
            makeMessagePhotoPlaceholder(from: messagePhoto)
        }
    }
    
    @ViewBuilder func makeMessagePhotoPlaceholder(from messagePhoto: MessagePhoto) -> some View {
        if let size = messagePhoto.photo.sizes.first(.iString) {
            Image(file: size.photo)
                .resizable()
                .scaledToFit()
                .blur(radius: 5)
        }
    }
}
