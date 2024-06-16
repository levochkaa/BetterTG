// AsyncTdFile.swift

import SwiftUI
import TDLibKit
import Combine

struct AsyncTdFile<Content: View, Placeholder: View>: View {
    let id: Int
    @ViewBuilder let content: (File) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    
    @State private var file: File?
    @State private var isDownloaded = true
    @State private var cancellables = Set<AnyCancellable>()
    
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
        .task(id: id) { await download(id) }
        .onAppear(perform: setPublishers)
    }
    
    private func setPublishers() {
        nc.publisher(&cancellables, for: .updateFile) { notification in
            guard let updateFile = notification.object as? UpdateFile, updateFile.file.id == id else { return }
            Task.main {
                withAnimation {
                    file = updateFile.file
                    isDownloaded = updateFile.file.local.isDownloadingCompleted
                }
            }
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
            withAnimation {
                self.file = file
            }
        } catch {
            log("Error downloading file: \(error)")
        }
    }
}
