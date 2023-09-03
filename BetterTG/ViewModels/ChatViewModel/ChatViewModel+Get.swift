// ChatViewModel+Get.swift

import TDLibKit
import PhotosUI

extension ChatViewModel {
    func getImages() async {
        Task.main {
            fetchedImages.removeAll()
        }
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.includeAssetSourceTypes = [.typeUserLibrary]
        fetchOptions.sortDescriptors = [.init(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 51
        
        let imageOptions = PHImageRequestOptions()
        imageOptions.version = .current
        imageOptions.resizeMode = .exact
        imageOptions.deliveryMode = .highQualityFormat
        imageOptions.isNetworkAccessAllowed = true
        imageOptions.isSynchronous = true
        
        let imageManager = PHCachingImageManager.default()
        
        PHAsset.fetchAssets(with: .image, options: fetchOptions).enumerateObjects { [self] asset, _, _ in
            var imageAsset = ImageAsset(asset: asset)
            
            imageManager.requestImage(
                for: imageAsset.asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: imageOptions
            ) { uiImage, _ in
                if let uiImage {
                    imageAsset.uiImage = uiImage
                    imageAsset.thumbnail = Image(uiImage: uiImage)
                    if let data = uiImage.jpegData(compressionQuality: 1) {
                        let imageUrl = URL(filePath: NSTemporaryDirectory())
                            .appending(path: "\(UUID().uuidString).png")
                        do {
                            try data.write(to: imageUrl, options: .atomic)
                            imageAsset.url = imageUrl
                        } catch {
                            log("Error getting data for an image: \(error)")
                        }
                    }
                }
            }
            
            Task.main { [imageAsset] in
                fetchedImages.append(imageAsset)
            }
        }
    }
    
    func toggleSelectedImage(_ index: Int, for imageAsset: ImageAsset) {
        if imageAsset.selected {
            fetchedImages[index].selected = false
            selectedImagesCount -= 1
        } else if selectedImagesCount < 10 {
            fetchedImages[index].selected = true
            selectedImagesCount += 1
        }
    }
    
    func delete(asset: PHAsset) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }
    }
    
    func getMessageReplyTo(from customMessage: CustomMessage?) -> MessageReplyTo? {
        guard let customMessage else { return nil }
        return .messageReplyToMessage(
            .init(
                chatId: customMessage.message.chatId,
                messageId: customMessage.message.id
            )
        )
    }
    
    func getReplyToMessage(_ replyTo: MessageReplyTo?) async -> Message? {
        if case .messageReplyToMessage(let messageReplyToMessage) = replyTo {
            return messageReplyToMessage.messageId != 0 ? await tdGetMessage(id: messageReplyToMessage.messageId) : nil
        }
        return nil
    }
    
    func getCustomMessage(fromId id: Int64) async -> CustomMessage? {
        guard let message = await tdGetMessage(id: id) else { return nil }
        let customMessage = await getCustomMessage(from: message)
        return customMessage
    }
    
    func getCustomMessage(from message: Message) async -> CustomMessage {
        let replyToMessage = await getReplyToMessage(message.replyTo)
        var customMessage = CustomMessage(message: message, replyToMessage: replyToMessage)
        if message.mediaAlbumId != 0 { customMessage.album.append(message) }
        customMessage.forwardedFrom = await getForwardedFrom(message.forwardInfo?.origin)
        
        if case .messageSenderUser(let messageSenderUser) = message.senderId {
            customMessage.senderUser = await tdGetUser(id: messageSenderUser.userId)
        }
        
        if case .messageSenderUser(let messageSenderUser) = replyToMessage?.senderId {
            customMessage.replyUser = await tdGetUser(id: messageSenderUser.userId)
        }
        
        return customMessage
    }
    
    func getForwardedFrom(_ origin: MessageForwardOrigin?) async -> String? {
        guard let origin else { return nil }
        
        switch origin {
            case .messageForwardOriginChat(let chat):
                if let title = await tdGetChat(id: chat.senderChatId)?.title {
                    return !chat.authorSignature.isEmpty ? "\(title) (\(chat.authorSignature))" : title
                } else {
                    return !chat.authorSignature.isEmpty ? chat.authorSignature : nil
                }
            case .messageForwardOriginChannel(let channel):
                if let title = await tdGetChat(id: channel.chatId)?.title {
                    return !channel.authorSignature.isEmpty ? "\(title) (\(channel.authorSignature))" : title
                } else {
                    return !channel.authorSignature.isEmpty ? channel.authorSignature : nil
                }
            case .messageForwardOriginHiddenUser(let messageForwardOriginHiddenUser):
                return messageForwardOriginHiddenUser.senderName
            case .messageForwardOriginMessageImport(let messageForwardOriginMessageImport):
                return messageForwardOriginMessageImport.senderName
            case .messageForwardOriginUser(let messageForwardOriginUser):
                return await tdGetUser(id: messageForwardOriginUser.senderUserId)?.firstName
        }
    }
    
    func getAnimojis(from entities: [TextEntity]) async -> [Animoji] {
        var animojis = [Animoji]()
        
        for entity in entities {
            guard case .textEntityTypeCustomEmoji(let textEntityTypeCustomEmoji) = entity.type,
                  let customEmoji = await tdGetCustomEmojiSticker(id: textEntityTypeCustomEmoji.customEmojiId),
                  case .stickerFullTypeCustomEmoji = customEmoji.fullType,
                  let file = await tdDownloadFile(id: customEmoji.sticker.id, synchronous: true)
            else { continue }
            
            let url = URL(filePath: file.local.path)
            let animoji: Animoji
            switch customEmoji.format {
                case .stickerFormatTgs:
                    animoji = Animoji(type: .tgs(url), realEmoji: customEmoji.emoji)
                case .stickerFormatWebp:
                    animoji = Animoji(type: .webp(url), realEmoji: customEmoji.emoji)
                case .stickerFormatWebm:
                    animoji = Animoji(type: .webm(url), realEmoji: customEmoji.emoji)
            }
            animojis.append(animoji)
        }
        
        return animojis
    }
    
    func getFormattedText(from content: MessageContent) -> FormattedText? {
        switch content {
            case .messageText(let messageText):
                guard !messageText.text.text.isEmpty else { return nil }
                return messageText.text
            case .messagePhoto(let messagePhoto):
                guard !messagePhoto.caption.text.isEmpty else { return nil }
                return messagePhoto.caption
            case .messageVoiceNote(let messageVoiceNote):
                guard !messageVoiceNote.caption.text.isEmpty else { return nil }
                return messageVoiceNote.caption
            default:
                return nil
        }
    }
    
    func getEntities(from text: AttributedString) -> [TextEntity] {
        var entities = [TextEntity]()
        let attributedText = NSAttributedString(text)
        let textRange = NSRange(location: 0, length: text.string.count)
        attributedText.enumerateAttributes(in: textRange) { attributes, range, _ in
            for attribute in attributes {
                guard let entity = getEntity(from: attribute, using: range) else { continue }
                entities.append(entity)
            }
        }
        return entities
    }
    
    func getEntity(from attribute: (key: NSAttributedString.Key, value: Any), using range: NSRange) -> TextEntity? {
        switch attribute.key {
            case .font:
                guard let uiFont = attribute.value as? UIFont else { return nil }
                switch uiFont {
                    case UIFont.bold:
                        return .init(.textEntityTypeBold, range: range)
                    case UIFont.italic:
                        return .init(.textEntityTypeItalic, range: range)
                    case UIFont.monospaced:
                        return .init(.textEntityTypeCode, range: range)
                    default:
                        break
                }
            case .link:
                guard let url = attribute.value as? URL else { return nil }
                return .init(.textEntityTypeTextUrl(.init(url: url.absoluteString)), range: range)
            case .strikethroughStyle:
                return .init(.textEntityTypeStrikethrough, range: range)
            case .underlineStyle:
                return .init(.textEntityTypeUnderline, range: range)
            case .backgroundColor:
                return .init(.textEntityTypeSpoiler, range: range)
            default:
                return nil
        }
        return nil
    }
}
