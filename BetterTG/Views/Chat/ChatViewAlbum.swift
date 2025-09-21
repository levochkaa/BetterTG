// ChatViewAlbum.swift

import SwiftUI
import TDLibKit

// MARK: - ChatViewAlbum

struct ChatViewAlbum: View {
    let album: [Message]
    let selection: Int64
    
    var body: some View {
        NavigationControllerWrapper {
            ChatViewAlbumRootView(album: album, selection: selection)
        }
        .ignoresSafeArea()
    }
}

// MARK: - ChatViewAlbumRootView

private struct ChatViewAlbumRootView: View {
    // MARK: Lifecycle

    init(album: [Message], selection: Int64) {
        self.album = album
        _selection = State(initialValue: selection)
    }

    // MARK: Internal

    @Environment(\.dismiss) var dismiss

    let album: [Message]

    var body: some View {
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
    }

    // MARK: Private

    @State private var selection: Int64
    @State private var photos = [Int: String]()

    private var toolbar: some View {
        HStack {
            Button(systemImage: "xmark.circle.fill") {
                dismiss()
            }
            
            Spacer()
            
            if let albumMessage = album.first(where: { $0.id == selection }),
               case .messagePhoto(let messagePhoto) = albumMessage.content,
               let size = messagePhoto.photo.sizes.getSize(.yBox),
               let path = photos[size.photo.id],
               FileManager.default.fileExists(atPath: path)
            {
                Button(systemImage: "square.and.arrow.up.circle.fill") {
                    showShareSheet([URL(filePath: path)])
                }
            }
        }
        .font(.title)
        .foregroundStyle(.white)
    }

    private func makeMessagePhoto(from messagePhoto: MessagePhoto) -> some View {
        TdImage(photo: messagePhoto.photo, size: .yBox, contentMode: .fit) { size, file in
            withAnimation { photos[size.photo.id] = file.local.path }
        }
    }
}
