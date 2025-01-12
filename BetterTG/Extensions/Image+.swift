// Image.swift

import SwiftUI
import TDLibKit

extension Image {
    init(file: TDLibKit.File) {
        self.init(uiImage: UIImage(contentsOfFile: file.local.path) ?? UIImage())
    }
    
    init?(data: Data?) {
        if let data, let uiImage = UIImage(data: data) {
            self.init(uiImage: uiImage)
        } else {
            return nil
        }
    }
}
