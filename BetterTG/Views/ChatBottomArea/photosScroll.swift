// photosScroll.swift

import SwiftUI

extension ChatBottomArea {
    @ViewBuilder var photosScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .center, spacing: 5) {
                ForEach(viewModel.displayedImages) { photo in
                    photo.image
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(10)
                        .transition(.scale.combined(with: .opacity))
                        .matchedGeometryEffect(id: "\(photo.id)", in: rootViewModel.namespace)
                        .onTapGesture {
                            withAnimation {
                                rootViewModel.openedItems = OpenedItems(
                                    id: photo.id,
                                    image: photo.image,
                                    photos: viewModel.displayedImages
                                )
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation {
                                    viewModel.displayedImages.removeAll(where: { photo.id == $0.id })
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
        .background(.gray6)
        .cornerRadius(15)
    }
}
