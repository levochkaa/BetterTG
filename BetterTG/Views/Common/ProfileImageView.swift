// ProfileImageView.swift

import SwiftUI
import TDLibKit

struct ProfileImageView: View {
    let photo: File?
    let minithumbnail: Minithumbnail?
    let title: String
    let userId: Int64
    
    var body: some View {
        ZStack {
            if let photo {
                AsyncTdImage(id: photo.id) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .contentShape(.contextMenuPreview, Circle())
                        .contextMenu {
                            Button("Save", systemImage: "square.and.arrow.down") {
                                guard let uiImage = UIImage(contentsOfFile: photo.local.path) else { return }
                                UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                            }
                        } preview: {
                            image
                                .resizable()
                                .scaledToFit()
                        }
                } placeholder: {
                    if let image = Image(data: minithumbnail?.data) {
                        image
                            .resizable()
                            .scaledToFit()
                    } else {
                        PlaceholderView(title: title, id: userId, fontSize: 20)
                    }
                }
            } else {
                PlaceholderView(title: title, id: userId, fontSize: 20)
            }
        }
        .clipShape(.circle)
    }
}
