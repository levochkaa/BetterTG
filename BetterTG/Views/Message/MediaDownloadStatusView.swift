// MediaDownloadStatusView.swift

import Combine
import TDLibKit
import UIKit

// MARK: - MediaDownloadStatusView

/// SemanticStatusNode over media auto-download didn't fetch (ChatMessageInteractiveMediaNode's `.download` and
/// `.progress`): a 50 pt dimmed circle with the download arrow, then a ring filling as the file downloads with a
/// cross that cancels.
final class MediaDownloadStatusView: UIControl {
    override var intrinsicContentSize: CGSize { CGSize(width: 50, height: 50) }

    var onDownload: (() -> Void)?
    var onCancel: (() -> Void)?

    private(set) var isDownloading = false

    private let arrowLayer = CAShapeLayer()
    private let crossLayer = CAShapeLayer()
    private let ringLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true
        clipsToBounds = true
        // mediaOverlayControlColors: black 45% in the day theme, 60% in the night theme.
        backgroundColor = UIColor { traits in
            UIColor.black.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.6 : 0.45)
        }
        for shape in [arrowLayer, crossLayer, ringLayer] {
            shape.fillColor = UIColor.clear.cgColor
            shape.strokeColor = UIColor.white.cgColor
            shape.lineCap = .round
            shape.lineJoin = .round
            layer.addSublayer(shape)
        }
        ringLayer.strokeEnd = 0
        isAccessibilityElement = true
        accessibilityTraits = .button
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 50),
            heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = bounds.width
        layer.cornerRadius = side / 2
        let factor = side / 50
        let center = CGPoint(x: side / 2, y: side / 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for shape in [arrowLayer, crossLayer, ringLayer] {
            shape.frame = bounds
        }
        arrowLayer.lineWidth = 2 * factor
        let arrow = UIBezierPath()
        arrow.move(to: CGPoint(x: center.x, y: center.y - 9 * factor))
        arrow.addLine(to: CGPoint(x: center.x, y: center.y + 9 * factor))
        arrow.move(to: CGPoint(x: center.x - 7 * factor, y: center.y + 2 * factor))
        arrow.addLine(to: CGPoint(x: center.x, y: center.y + 9 * factor))
        arrow.addLine(to: CGPoint(x: center.x + 7 * factor, y: center.y + 2 * factor))
        arrowLayer.path = arrow.cgPath
        crossLayer.lineWidth = max(1.3, 2 * factor)
        let cross = 14 * factor
        let crossPath = UIBezierPath()
        crossPath.move(to: CGPoint(x: center.x - cross / 2, y: center.y - cross / 2))
        crossPath.addLine(to: CGPoint(x: center.x + cross / 2, y: center.y + cross / 2))
        crossPath.move(to: CGPoint(x: center.x + cross / 2, y: center.y - cross / 2))
        crossPath.addLine(to: CGPoint(x: center.x - cross / 2, y: center.y + cross / 2))
        crossLayer.path = crossPath.cgPath
        let ringWidth = max(1.6, 2.25 * factor)
        ringLayer.lineWidth = ringWidth
        ringLayer.path = UIBezierPath(
            arcCenter: center,
            radius: (side - ringWidth - 5) / 2,
            startAngle: -.pi / 2,
            endAngle: .pi * 3 / 2,
            clockwise: true,
        ).cgPath
        CATransaction.commit()
    }

    func showDownload() {
        isDownloading = false
        isHidden = false
        arrowLayer.isHidden = false
        crossLayer.isHidden = true
        ringLayer.isHidden = true
        ringLayer.strokeEnd = 0
        accessibilityLabel = L10n.betterTG("Accessibility.Download")
    }

    /// The share downloaded so far; the ring never shows less than a sliver, as the upload ring doesn't.
    func showProgress(_ fraction: CGFloat) {
        isDownloading = true
        isHidden = false
        arrowLayer.isHidden = true
        crossLayer.isHidden = false
        ringLayer.isHidden = false
        ringLayer.strokeEnd = max(0.027, min(1, fraction))
        accessibilityLabel = L10n.telegram("Common.Cancel")
    }

    func hide() {
        isDownloading = false
        isHidden = true
    }

    @objc private func tapped() {
        if isDownloading {
            onCancel?()
        } else {
            onDownload?()
        }
    }
}

// MARK: - DeferredMediaDownload

/// A file auto-download left for the user (shouldDownloadMediaAutomatically said no): the status view shows the
/// arrow, a tap downloads it with the ring following TDLib's progress, a second tap cancels, and the owner gets the
/// file once it is complete. A download already running, from another bubble or the gallery, shows as progress.
@MainActor final class DeferredMediaDownload {
    private let fileID: Int
    private let client: TDLibClient
    private let source: TdUpdateSource
    private weak var status: MediaDownloadStatusView?
    private let onComplete: (File) -> Void
    private var updates: AnyCancellable?
    private var refreshTask: Task<Void, Never>?

    var isDownloading: Bool { status?.isDownloading == true }

    init?(file: File, client: TDLibClient, status: MediaDownloadStatusView, onComplete: @escaping (File) -> Void) {
        guard let source = TDLib.shared.activeUpdateSource, source.clientID == client.id else { return nil }
        self.fileID = file.id
        self.client = client
        self.source = source
        self.status = status
        self.onComplete = onComplete
        status.onDownload = { [weak self] in self?.start() }
        status.onCancel = { [weak self] in self?.cancel() }
        self.updates = TDImageLoadingView.fileUpdates(source: source, fileID: file.id)
            .sink { [weak self] file in self?.apply(file) }
        apply(file)
        // The message's copy of the file can be older than TDLib's.
        self.refreshTask = Task { [weak self, client] in
            guard let file = try? await client.getFile(fileId: file.id) else { return }
            self?.apply(file)
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    func start() {
        status?.showProgress(0)
        let client = client
        let fileID = fileID
        Task { [weak self] in
            let file = try? await client.downloadFile(
                fileId: fileID,
                limit: 0,
                offset: 0,
                priority: 16,
                synchronous: false,
            )
            guard let file else { return }
            self?.apply(file)
        }
    }

    func cancel() {
        status?.showDownload()
        let client = client
        let fileID = fileID
        Task { _ = try? await client.cancelDownloadFile(fileId: fileID, onlyIfPending: false) }
    }

    private func apply(_ file: File) {
        guard file.id == fileID, TDLib.shared.activeUpdateSource == source else { return }
        if file.local.isDownloadingCompleted, !file.local.path.isEmpty {
            updates = nil
            status?.hide()
            onComplete(file)
        } else if file.local.isDownloadingActive {
            let total = max(file.size, file.expectedSize)
            status?.showProgress(total > 0 ? CGFloat(file.local.downloadedSize) / CGFloat(total) : 0)
        } else if status?.isDownloading != true {
            status?.showDownload()
        }
    }
}
