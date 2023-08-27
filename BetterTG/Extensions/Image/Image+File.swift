// Image+File.swift

import TDLibKit

extension Image {
    init(file: TDLibKit.File) {
        self.init(uiImage: UIImage(contentsOfFile: file.local.path) ?? UIImage())
    }
}
