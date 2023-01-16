// Chat+messageContent.swift

import SwiftUI
import TDLibKit

extension ChatViewModel {
    func makeInputMessageContent(for url: URL) -> InputMessageContent {
        let path = url.path()
        
        let image = UIImage(contentsOfFile: path)!
        
        let input: InputFile = .inputFileLocal(.init(path: path))
        
        return .inputMessagePhoto(
            InputMessagePhoto(
                addedStickerFileIds: [],
                caption: FormattedText(entities: [], text: text),
                height: Int(image.size.height),
                photo: input,
                thumbnail: InputThumbnail(
                    height: Int(image.size.height),
                    thumbnail: input,
                    width: Int(image.size.width)
                ),
                ttl: 0,
                width: Int(image.size.width)
            )
        )
    }
}
