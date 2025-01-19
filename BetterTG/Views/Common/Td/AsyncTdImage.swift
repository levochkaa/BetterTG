// AsyncTdImage.swift

import SwiftUI
import TDLibKit

struct AsyncTdImage<Content: View, Placeholder: View>: View {
    let id: Int
    @ViewBuilder let content: (Image, File) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    
    @State private var file: File?
    @State private var image: Image?
    
    var body: some View {
        ZStack {
            if let image, let file {
                content(image, file)
            } else {
                placeholder()
            }
        }
        .task(id: id) { await download(id) }
        .onReceive(nc.publisher(for: .updateFile)) { updateFile in
            guard updateFile.file.id == id else { return }
            Task.main { await setImage(from: updateFile.file) }
        }
    }
    
    private func download(_ id: Int? = nil) async {
        do {
            let file = try await td.downloadFile(
                fileId: id ?? self.id,
                limit: 0,
                offset: 0,
                priority: 1,
                synchronous: false
            )
            await setImage(from: file)
        } catch {
            log("Error downloading file: \(error)")
        }
    }
    
    @MainActor private func setImage(from file: File) async {
        guard file.local.isDownloadingCompleted,
              let uiImage = await UIImage(contentsOfFile: file.local.path)?.byPreparingForDisplay()
        else { return }
        withAnimation {
            self.file = file
            self.image = Image(uiImage: uiImage)
        }
    }
}
