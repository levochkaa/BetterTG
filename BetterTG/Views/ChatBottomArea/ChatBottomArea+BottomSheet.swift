// ChatBottomArea+BottomSheet.swift

import PhotosUI

extension ChatBottomArea {
    @ViewBuilder var bottomSheet: some View {
        NavigationStack {
            @Bindable var viewModel = viewModel
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
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .blue)
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
            Task.main(delay: Utils.defaultAnimationDuration * 2) {
                withAnimation {
                    viewModel.toggleSelectedImage(index, for: imageAsset)
                }
            }
        }
        
        DividerAround {
            Button("Send", systemImage: "paperplane.fill") {
                viewModel.showBottomSheet = false
                viewModel.sendMessagePhoto(imageAsset: imageAsset)
            }
        }
        
        Button("Delete", systemImage: "trash.fill", role: .destructive) {
            viewModel.delete(asset: imageAsset.asset)
        }
    }
}
