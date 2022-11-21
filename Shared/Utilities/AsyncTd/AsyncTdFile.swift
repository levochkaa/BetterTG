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
    private let nc = NotificationCenter.default
    private var cancellable = Set<AnyCancellable>()

    @State private var file: File?
    @State private var isDownloaded = true

    init(
        id: Int,
        content: @escaping (File) -> Content,
        placeholder: @escaping () -> Placeholder,
        file: File? = nil,
        isDownloaded: Bool = true
    ) {
        self.id = id
        self.content = content
        self.placeholder = placeholder
        self.file = file
        self.isDownloaded = isDownloaded
        
        self.setPublishers()
    }
    
    mutating func setPublishers() {
        nc.publisher(for: .file, in: &cancellable) { [self] notification in
            if let updateFile = notification.object as? UpdateFile,
               updateFile.file.id == self.id {
                self.file = updateFile.file
                self.isDownloaded = updateFile.file.local.isDownloadingCompleted
            }
        }
    }

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
//            .scaledToFill()
        }
        .animation(.easeInOut, value: isDownloaded)
        .animation(.easeInOut, value: file)
        .onChange(of: id) { id in
            download(id)
        }
        .onAppear {
            download()
        }
    }

    // swiftlint:disable force_cast
    private func download(_ id: Int? = nil) {
        Task {
//            logger.log("Downloading file \(id != nil ? id! : self.id)", level: .info)
            do {
                self.file = try await tdApi.downloadFile(
                    fileId: id != nil ? id! : self.id,
                    limit: 0,
                    offset: 0,
                    priority: 4,
                    synchronous: false)
            } catch {
                logger.log(
                    """
                    Failed to download file with ID \(id != nil ? id! : self.id), \
                    reason: \((error as! TDLibKit.Error).message)
                    """,
                    level: .error
                )
            }
        }
    }
}
