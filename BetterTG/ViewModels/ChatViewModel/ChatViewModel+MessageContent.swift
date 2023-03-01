// ChatViewModel+MessageContent.swift

import SwiftUI
import TDLibKit

extension ChatViewModel {
    func makeInputMessageContent(for url: URL) -> InputMessageContent {
        let path = url.path()
        
        let image = UIImage(contentsOfFile: path) ?? UIImage()
        
        let input: InputFile = .inputFileLocal(.init(path: path))
        
        return .inputMessagePhoto(
            InputMessagePhoto(
                addedStickerFileIds: [],
                caption: FormattedText(entities: [], text: text.string),
                hasSpoiler: false,
                height: Int(image.size.height),
                photo: input,
                selfDestructTime: 0,
                thumbnail: InputThumbnail(
                    height: Int(image.size.height),
                    thumbnail: input,
                    width: Int(image.size.width)
                ),
                width: Int(image.size.width)
            )
        )
    }
}
