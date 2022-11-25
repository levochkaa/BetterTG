// AsyncTdFile.swift

import SwiftUI
import Combine
import TDLibKit

struct AsyncTdFile<Content: View, Placeholder: View>: View {
    let id: Int
    @ViewBuilder let content: (File) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    private let tdApi = TdApi.shared
    private let logger = Logger(label: "AsyncTdFile")
    private let nc: NotificationCenter = .default

    @State private var file: File?
    @State private var isDownloaded = true

    @ViewBuilder
    var body: some View {
        ZStack {
            Group {
                if isDownloaded {
                    if let file = file {
                        content(file)
                    } else {
                        placeholder()
                    }
                } else {
                    placeholder()
                }
            }
            .transition(.opacity)
        }
        .animation(.easeInOut, value: isDownloaded)
        .animation(.easeInOut, value: file)
        .onReceive(nc.publisher(for: .file)) { notification in
            if let updateFile = notification.object as? UpdateFile,
               updateFile.file.id == self.id {
                file = updateFile.file
                isDownloaded = updateFile.file.local.isDownloadingCompleted
            }
        }
        .onChange(of: id) { id in
            download(id)
        }
        .onAppear {
            download()
        }
    }

    private func download(_ id: Int? = nil) {
        Task {
            do {
                self.file = try await tdApi.downloadFile(
                    fileId: id ?? self.id,
                    limit: 0,
                    offset: 0,
                    priority: 4,
                    synchronous: false
                )
            } catch {
                guard let tdError = error as? TDLibKit.Error else { return }
                logger.log("Failed to download file with ID \(id ?? self.id), reason: \(tdError.message)")
            }
        }
    }
}
