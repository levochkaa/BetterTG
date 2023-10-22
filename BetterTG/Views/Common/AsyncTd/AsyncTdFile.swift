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
        .animation(.easeInOut, value: isDownloaded)
        .animation(.easeInOut, value: file)
        .onReceive(nc.publisher(for: .file)) { notification in
            guard let updateFile = notification.object as? UpdateFile else { return }
            if updateFile.file.id == id {
                file = updateFile.file
                isDownloaded = updateFile.file.local.isDownloadingCompleted
            }
        }
        .onChange(of: id) { _, id in
            download(id)
        }
        .onAppear {
            download()
        }
    }
    
    private func download(_ id: Int? = nil) {
        Task {
            do {
                self.file = try await td.downloadFile(
                    fileId: id ?? self.id,
                    limit: 0,
                    offset: 0,
                    priority: 4,
                    synchronous: false
                )
            } catch {
                log("Error downloading file: \(error)")
            }
        }
    }
}
