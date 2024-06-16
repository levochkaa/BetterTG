// AsyncTdFile.swift

import SwiftUI
import TDLibKit

struct AsyncTdFile<Content: View, Placeholder: View>: View {
    
    let id: Int
    @ViewBuilder let content: (File) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    
    @State private var file: File?
    @State private var isDownloaded = true
    
    var body: some View {
        ZStack {
            Group {
                if let file, isDownloaded {
                    content(file)
                } else {
                    placeholder()
                }
            }
            .transition(.opacity)
        }
        .onReceive(nc.publisher(for: .updateFile)) { notification in
            guard let updateFile = notification.object as? UpdateFile, updateFile.file.id == id else { return }
            withAnimation {
                file = updateFile.file
                isDownloaded = updateFile.file.local.isDownloadingCompleted
            }
        }
        .task(id: id) { await download(id) }
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
            withAnimation {
                self.file = file
            }
        } catch {
            log("Error downloading file: \(error)")
        }
    }
}
