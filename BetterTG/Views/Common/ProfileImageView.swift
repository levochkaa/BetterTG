// ProfileImageView.swift

import SwiftUI
import TDLibKit

struct ProfileImageView: View {
    let photo: File?
    let minithumbnail: Minithumbnail?
    let title: String
    let userId: Int64
    var fontSize: CGFloat = 20
    
    var body: some View {
        ZStack {
            if let photo {
                AsyncTdImage(id: photo.id) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .contentShape(.contextMenuPreview, Circle())
                        .customContextMenu([
                            .button(title: "Save", systemImage: "square.and.arrow.down") {
                                guard let uiImage = UIImage(contentsOfFile: photo.local.path) else { return }
                                UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                            }
                        ]) {
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
                        PlaceholderView(title: title, id: userId, fontSize: fontSize)
                    }
                }
            } else {
                PlaceholderView(title: title, id: userId, fontSize: fontSize)
            }
        }
        .clipShape(.circle)
    }
}

struct PlaceholderView: View {
    let title: String
    let id: Int64
    let fontSize: CGFloat
    
    var body: some View {
        Text(String(title.prefix(1).capitalized))
            .font(.system(size: fontSize, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(userId: id).gradient)
    }
}
