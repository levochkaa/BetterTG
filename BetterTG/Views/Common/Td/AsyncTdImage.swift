// AsyncTdImage.swift

import ImageIO
import SwiftUI
import TDLibKit

// MARK: - AsyncTdImage

struct AsyncTdImage<Content: View, Placeholder: View>: View {
    // MARK: Internal

    let id: Int
    @ViewBuilder let content: (Image, File) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    
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
    
    // MARK: Private

    @State private var file: File?
    @State private var image: Image?
    
    private func download(_ id: Int? = nil) async {
        do {
            let file = try await td.downloadFile(
                fileId: id ?? self.id,
                limit: 0,
                offset: 0,
                priority: 1,
                synchronous: false,
            )
            await setImage(from: file)
        } catch {
            log("Error downloading file: \(error)")
        }
    }
    
    @MainActor private func setImage(from file: File) async {
        guard file.local.isDownloadingCompleted else { return }
        let localPath = file.local.path
        guard let uiImage = await Task.detached(priority: .userInitiated, operation: {
            createThumbnailImage(at: localPath)
        })
        .value else { return }

        withAnimation {
            self.file = file
            image = Image(uiImage: uiImage)
        }
    }
}

private func createThumbnailImage(at localPath: String) -> UIImage? {
    guard FileManager.default.fileExists(atPath: localPath), // Avoid spamming logs for missing files.
          let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: localPath) as CFURL, nil)
    else { return nil }

    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let maxPixelSize = max(
        (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0,
        (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0,
    )

    guard maxPixelSize > 0,
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceCreateThumbnailWithTransform: true,
              kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
              kCGImageSourceShouldCache: false,
              kCGImageSourceShouldCacheImmediately: false,
          ] as CFDictionary)
    else { return nil }

    return UIImage(cgImage: cgImage)
}
