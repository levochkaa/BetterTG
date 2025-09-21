// AsyncTdFile.swift

import Combine
import SwiftUI
import TDLibKit

struct AsyncTdFile<Content: View, Placeholder: View>: View {
    // MARK: Internal

    let id: Int
    @ViewBuilder let content: (File) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    
    var body: some View {
        ZStack {
            Group {
                if let file, file.local.isDownloadingCompleted {
                    content(file)
                } else {
                    placeholder()
                }
            }
            .transition(.opacity)
        }
        .task(id: id) { await download(id) }
        .onReceive(nc.publisher(for: .updateFile)) { updateFile in
            guard updateFile.file.id == id else { return }
            Task.main { withAnimation { file = updateFile.file } }
        }
    }
    
    // MARK: Private

    @State private var file: File?
    
    private func download(_ id: Int? = nil) async {
        do {
            let file = try await td.downloadFile(
                fileId: id ?? self.id,
                limit: 0,
                offset: 0,
                priority: 1,
                synchronous: false,
            )
            withAnimation {
                self.file = file
            }
        } catch {
            log("Error downloading file: \(error)")
        }
    }
}
