// bottomSheet.swift

import SwiftUI

extension ChatBottomArea {
    @ViewBuilder var bottomSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .center, spacing: 10) {
                    ForEach($viewModel.fetchedImages) { $imageAsset in
                        if let thummbail = imageAsset.thumbnail {
                            thummbail
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
                                .onTapGesture {
                                    withAnimation {
                                        imageAsset.selected.toggle()
                                    }
                                }
                                .contextMenu {
                                    Button(
                                        imageAsset.selected ? "Deselect" : "Select",
                                        systemImage: imageAsset.selected ? "circle" : "checkmark.circle.fill"
                                    ) {
                                        Task.async(after: Utils.defaultAnimationDuration + 0.05) {
                                            withAnimation {
                                                imageAsset.selected.toggle()
                                            }
                                        }
                                    }
                                    
                                    Divider()
                                    
                                    Button("Send", systemImage: "paperplane.fill") {
                                        showBottomSheet = false
                                        viewModel.sendMessagePhoto(imageAsset: imageAsset)
                                    }
                                    
                                    Divider()
                                    
                                    Button("Delete", systemImage: "trash.fill", role: .destructive) {
                                        viewModel.delete(asset: imageAsset.asset)
                                    }
                                } preview: {
                                    thummbail
                                        .resizable()
                                        .scaledToFit()
                                }
                        } else {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(.gray6)
                                .frame(width: Utils.bottomSheetPhotoWidth, height: Utils.bottomSheetPhotoWidth)
                                .overlay {
                                    Image(systemName: "exclamationmark.square")
                                        .font(.largeTitle)
                                }
                                .onAppear {
                                    if let uiImage = imageAsset.uiImage, imageAsset.thumbnail == nil {
                                        imageAsset.thumbnail = Image(uiImage: uiImage)
                                        if let data = uiImage.jpegData(compressionQuality: 0.8) {
                                            let imageUrl = URL(filePath: NSTemporaryDirectory())
                                                .appending(path: "\(UUID().uuidString).png")
                                            do {
                                                try data.write(to: imageUrl, options: .atomic)
                                                imageAsset.url = imageUrl
                                            } catch {
                                                log("Error getting data for an image: \(error)")
                                            }
                                        }
                                    }
                                }
                            
                        }
                    }
                }
                .padding(10)
                .onAppear {
                    viewModel.getImages()
                }
            }
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showBottomSheet = false
                        viewModel.loadPhotos()
                    }
                    .bold()
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showBottomSheet = false
                        viewModel.fetchedImages = viewModel.fetchedImages.map { $0.deselected() }
                    }
                }
            }
        }
    }
}
