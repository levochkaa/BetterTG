// Image+File.swift

import SwiftUI
import TDLibKit

extension Image {
    init(file: TDLibKit.File) {
        if let uiImage = UIImage(contentsOfFile: file.local.path) {
            self.init(uiImage: uiImage)
        } else {
            self.init(uiImage: UIImage())
        }
    }
}
