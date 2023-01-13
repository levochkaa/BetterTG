// ChatBottomArea+PhotosScroll.swift

import SwiftUI

extension ChatBottomArea {
    @ViewBuilder var photosScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .center, spacing: 5) {
                ForEach(viewModel.displayedPhotos) { photo in
                    photo.image
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(10)
                        .transition(.scale.combined(with: .opacity))
                        .matchedGeometryEffect(
                            id: "\(photo.id)",
                            in: rootNamespace!,
                            properties: .frame
                        )
                        .onTapGesture {
                            withAnimation {
                                self.openedPhotoInfo = OpenedPhotoInfo(
                                    openedPhotoMessageId: photo.id,
                                    openedPhoto: photo.image
                                )
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation {
                                    viewModel.displayedPhotos.removeAll(where: { photo.id == $0.id })
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .foregroundColor(.white)
                                    .padding(5)
                            }
                        }
                }
            }
        }
        .frame(height: 120)
        .cornerRadius(15)
        .padding(5)
        .background(Color.gray6)
        .cornerRadius(15)
    }
}
