// bottomSheet.swift

import SwiftUI
import PhotosUI

extension ChatBottomArea {
    @ViewBuilder var bottomSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, alignment: .center, spacing: 10) {
                    ForEach(Array(viewModel.fetchedImages.enumerated()), id: \.offset) { index, imageAsset in
                        if let thummbail = imageAsset.thumbnail {
                            fetchedImageView(index, for: imageAsset, with: thummbail)
                        } else {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(.gray6)
                                .frame(width: Utils.bottomSheetPhotoWidth, height: Utils.bottomSheetPhotoWidth)
                                .overlay {
                                    Image(systemName: "exclamationmark.square")
                                        .font(.largeTitle)
                                }
                        }
                    }
                }
                .padding(10)
            }
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.showBottomSheet = false
                        viewModel.loadPhotos()
                    }
                    .bold()
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.showBottomSheet = false
                        viewModel.fetchedImages = viewModel.fetchedImages.map { $0.deselected() }
                        viewModel.selectedImagesCount = 0
                    }
                }
                
                ToolbarItem(placement: .bottomBar) {
                    Text("\(viewModel.selectedImagesCount)/10 items selected")
                }
            }
            .toolbarTitleMenu {
                Button("Camera") {
                    viewModel.showCameraView = true
                }
            }
            .fullScreenCover(isPresented: $viewModel.showCameraView) {
                NavigationStack {
                    CameraView()
                        .navigationTitle("Camera")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarTitleMenu {
                            Button("Gallery") {
                                viewModel.showCameraView = false
                            }
                        }
                }
            }
        }
    }
    
    @ViewBuilder func fetchedImageView(_ index: Int, for imageAsset: ImageAsset, with thumbnail: Image) -> some View {
        thumbnail
            .resizable()
            .scaledToFill()
            .frame(width: Utils.bottomSheetPhotoWidth, height: Utils.bottomSheetPhotoWidth)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .contentShape(RoundedRectangle(cornerRadius: 15))
            .overlay(alignment: .topTrailing) {
                Group {
                    if imageAsset.selected {
                        Image(systemName: "checkmark.circle.fill")
                            .transition(.scale)
                    } else {
                        Image(systemName: "circle")
                            .transition(.scale)
                    }
                }
                .padding(5)
            }
            .onTapGesture { [imageAsset] in
                withAnimation {
                    viewModel.toggleSelectedImage(index, for: imageAsset)
                }
            }
            .contextMenu {
                imageContextMenu(index, for: imageAsset)
            } preview: {
                thumbnail
                    .resizable()
                    .scaledToFit()
            }
    }
    
    @ViewBuilder func imageContextMenu(_ index: Int, for imageAsset: ImageAsset) -> some View {
        Button(
            imageAsset.selected ? "Deselect" : "Select",
            systemImage: imageAsset.selected ? "circle" : "checkmark.circle.fill"
        ) {
            Task.async(after: Utils.defaultAnimationDuration * 2) {
                withAnimation {
                    viewModel.toggleSelectedImage(index, for: imageAsset)
                }
            }
        }
        
        Divider()
        
        Button("Send", systemImage: "paperplane.fill") {
            viewModel.showBottomSheet = false
            viewModel.sendMessagePhoto(imageAsset: imageAsset)
        }
        
        Divider()
        
        Button("Delete", systemImage: "trash.fill", role: .destructive) {
            viewModel.delete(asset: imageAsset.asset)
        }
    }
}
