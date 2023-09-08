// ChatBottomArea+BottomSheet.swift

import PhotosUI

extension ChatBottomArea {
    @ViewBuilder var bottomSheet: some View {
        NavigationStack {
            @Bindable var viewModel = viewModel
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, alignment: .center, spacing: 10) {
                    ForEach(viewModel.fetchedImages) { imageAsset in
                        fetchedImageView(for: imageAsset)
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
                    }
                }
                
                ToolbarItem(placement: .bottomBar) {
                    Text("\(viewModel.fetchedImages.filter(\.selected).count)/10 items selected")
                }
            }
            .toolbarTitleMenu {
                Button("Camera") {
                    viewModel.showCameraView = true
                }
            }
        }
    }
    
    @ViewBuilder func fetchedImageView(for imageAsset: ImageAsset) -> some View {
        imageAsset.image
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
            .onTapGesture {
                withAnimation {
                    viewModel.toggleSelectedImage(for: imageAsset)
                }
            }
            .contextMenu {
                Button(
                    imageAsset.selected ? "Deselect" : "Select",
                    systemImage: imageAsset.selected ? "circle" : "checkmark.circle.fill"
                ) {
                    Task.main(delay: Utils.defaultAnimationDuration * 2) {
                        withAnimation {
                            viewModel.toggleSelectedImage(for: imageAsset)
                        }
                    }
                }
                
                Divider()
                
                Button("Send", systemImage: "paperplane.fill") {
                    viewModel.showBottomSheet = false
                    viewModel.sendMessagePhoto(imageAsset: imageAsset)
                }
            } preview: {
                imageAsset.image
                    .resizable()
                    .scaledToFit()
            }
    }
}
