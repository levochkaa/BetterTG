// PollAttachProbe.swift

#if DEBUG
    import TDLibKit
    import UIKit

    /// Launch with `-ui-probe-poll-attach`. Once an account is active it opens the poll creator with a question, a
    /// drawn test photo on the poll (its description row) and four options: a photo, a link without its web page
    /// (the creator asks getLinkPreview for it), a venue and a generated sticker. Their thumbnails and the Replace and
    /// Delete menu with its preview are checked without photo library access. `-ui-probe-poll-attach upload` also
    /// runs a simulated upload on the first option's photo; `-ui-probe-poll-attach tabs` opens the description's
    /// attachment sheet. Nothing is sent or uploaded.
    @MainActor enum PollAttachProbe {
        private static let photoSize = CGSize(width: 800, height: 600)

        /// A place as the location picker's venue search gives it.
        private static var venue: InputMessageContent {
            .inputMessageVenue(TDNativeInputMessageVenue(venue: TDNativeVenue(
                location: TDNativeLocation(latitude: 37.7853, longitude: -122.4021, horizontalAccuracy: 0),
                title: "Yerba Buena Gardens",
                address: "750 Howard St",
                provider: "",
                id: "",
                type: "parks_outdoors/park",
            )))
        }

        static func runIfRequested(in window: UIWindow) {
            let arguments = ProcessInfo.processInfo.arguments
            guard let flag = arguments.firstIndex(of: "-ui-probe-poll-attach") else { return }
            let mode = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : ""
            Task { @MainActor in
                for _ in 0..<60 where TDLib.shared.activeAccountID == nil {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                guard let accountID = TDLib.shared.activeAccountID else { return }
                try? await Task.sleep(for: .seconds(2))
                var presenter = window.rootViewController
                while let presented = presenter?.presentedViewController {
                    presenter = presented
                }
                guard let presenter,
                      let pollMedia = makeMedia(color: .systemBlue, label: "POLL"),
                      let optionMedia = makeMedia(color: .systemOrange, label: "1")
                else { return }
                let poll = CreatePollViewController(
                    isChannel: false,
                    client: TDLib.shared.activeClient,
                    accountID: accountID,
                    chatID: 0,
                ) { _ in }
                let sticker = (try? StickerPeekProbe.makeStickers())?.first.map { PollDraftMedia.sticker($0) }
                poll.applyProbeDraft(
                    question: "Poll attachment probe",
                    options: [
                        ("Photo option", optionMedia),
                        ("Link option", PollDraftMedia.link("https://telegram.org")),
                        ("Venue option", PollDraftMedia.location(venue)),
                        ("Sticker option", sticker),
                    ],
                    pollMedia: pollMedia,
                )
                presenter.present(poll.makeNavigationController(), animated: true) {
                    switch mode {
                    case "upload": poll.simulateProbeUpload(ofOptionAt: 0)
                    case "tabs": poll.openProbeAttachmentSheet()
                    default: break
                    }
                }
            }
        }

        /// A test photo written to the composer's file store, as a gallery pick is.
        private static func makeMedia(color: UIColor, label: String) -> PollDraftMedia? {
            let image = makePhoto(color: color, label: label)
            guard let data = image.jpegData(compressionQuality: 0.9),
                  let url = try? SelectedDocumentFileStore.makeFileURL(named: "poll-probe.jpg"),
                  (try? data.write(to: url)) != nil
            else { return nil }
            return PollDraftMedia.photo(at: url, preview: image)
        }

        private static func makePhoto(color: UIColor, label: String) -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: photoSize, format: format).image { context in
                color.setFill()
                context.fill(CGRect(origin: .zero, size: photoSize))
                UIColor.white.withAlphaComponent(0.5).setFill()
                for x in stride(from: CGFloat(0), through: photoSize.width, by: 100) {
                    context.fill(CGRect(x: x - 1, y: 0, width: 2, height: photoSize.height))
                }
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 220),
                    .foregroundColor: UIColor.white,
                ]
                let text = label as NSString
                let size = text.size(withAttributes: attributes)
                text.draw(
                    at: CGPoint(x: (photoSize.width - size.width) / 2, y: (photoSize.height - size.height) / 2),
                    withAttributes: attributes,
                )
            }
        }
    }
#endif
