// View+CustomContextMenu.swift

import SwiftUI

enum ContextMenuAction {
    case divider
    case button(title: String, systemImage: String, attributes: UIMenuElement.Attributes = [], action: () -> Void)
    case menu(title: String, systemImage: String? = nil, children: [ContextMenuAction?])
}

extension [ContextMenuAction?] {
    func uiMenu(title: String = "", systemImage: String? = nil) -> UIMenu {
        var elements = [UIMenuElement]()
        for action in self {
            guard let action else { continue }
            switch action {
            case .divider:
                let childre = elements
                elements.removeAll()
                elements.append(UIMenu(options: .displayInline, children: childre))
            case .button(let title, let systemImage, let attributes, let action):
                elements.append(
                    UIAction(
                        title: title,
                        image: UIImage(systemName: systemImage),
                        attributes: attributes,
                        handler: { _ in action() }
                    )
                )
            case .menu(let title, let systemImage, let children):
                elements.append(children.uiMenu(title: title, systemImage: systemImage))
            }
        }
        return
            if let systemImage {
                UIMenu(title: title, image: UIImage(systemName: systemImage), children: elements)
            } else {
                UIMenu(title: title, children: elements)
            }
    }
}

extension View {
    func customContextMenu(
        cornerRadius: CGFloat = 0,
        _ actions: [ContextMenuAction?] = [],
        didTapPreview: (() -> Void)? = nil,
        onAppear: @escaping () -> Void = {},
        onDisappear: @escaping () -> Void = {}
    ) -> some View {
        overlay {
            CustomContextMenuView(
                cornerRadius: cornerRadius,
                menu: actions.uiMenu(),
                preview: self,
                didTapPreview: didTapPreview,
                onAppear: onAppear,
                onDisappear: onDisappear
            )
        }
    }
    
    func customContextMenu<Content: View>(
        cornerRadius: CGFloat = 0,
        _ actions: [ContextMenuAction?] = [],
        @ViewBuilder _ preview: () -> Content,
        didTapPreview: (() -> Void)? = nil,
        onAppear: @escaping () -> Void = {},
        onDisappear: @escaping () -> Void = {}
    ) -> some View {
        overlay {
            CustomContextMenuView(
                cornerRadius: cornerRadius,
                menu: actions.uiMenu(),
                preview: preview(),
                didTapPreview: didTapPreview,
                onAppear: onAppear,
                onDisappear: onDisappear
            )
        }
    }
}

private struct CustomContextMenuView<Content: View>: UIViewRepresentable {
    let cornerRadius: CGFloat
    let menu: UIMenu
    let preview: Content
    let didTapPreview: (() -> Void)?
    let onAppear: () -> Void
    let onDisappear: () -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.layer.cornerRadius = cornerRadius
        view.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
        return view
    }
    
    func updateUIView(_: UIView, context _: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        let parent: CustomContextMenuView
        
        init(_ parent: CustomContextMenuView) {
            self.parent = parent
        }
        
        func contextMenuInteraction(
            _: UIContextMenuInteraction,
            configurationForMenuAtLocation _: CGPoint
        ) -> UIContextMenuConfiguration? {
            UIContextMenuConfiguration(
                identifier: nil,
                previewProvider: { [weak self] () -> UIViewController? in
                    guard let self else { return nil }
                    return PreviewHostingController(
                        rootView: parent.preview,
                        onAppear: parent.onAppear,
                        onDisappear: parent.onDisappear
                    )
                },
                actionProvider: { [weak self] _ in
                    self?.parent.menu ?? nil
                }
            )
        }
        
        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            previewForHighlightingMenuWithConfiguration _: UIContextMenuConfiguration
        ) -> UITargetedPreview? {
            guard let view = interaction.view else { return nil }
            return UITargetedPreview(view: view, parameters: UIPreviewParameters(backgroundColor: .clear))
        }
        
        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            previewForDismissingMenuWithConfiguration _: UIContextMenuConfiguration
        ) -> UITargetedPreview? {
            guard let view = interaction.view else { return nil }
            return UITargetedPreview(view: view, parameters: UIPreviewParameters(backgroundColor: .clear))
        }
        
        func contextMenuInteraction(
            _: UIContextMenuInteraction,
            willPerformPreviewActionForMenuWith _: UIContextMenuConfiguration,
            animator: UIContextMenuInteractionCommitAnimating
        ) {
            if let didTapPreview = parent.didTapPreview {
                animator.addCompletion(didTapPreview)
            }
        }
    }
}

private final class PreviewHostingController<Content: View>: UIHostingController<Content> {
    private var onAppear: () -> Void = {}
    private var onDisappear: () -> Void = {}
    
    init(rootView: Content, onAppear: @escaping () -> Void, onDisappear: @escaping () -> Void) {
        super.init(rootView: rootView)
        self.view.backgroundColor = .clear
        self.onAppear = onAppear
        self.onDisappear = onDisappear
    }
    
    @available(*, unavailable)
    dynamic required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        preferredContentSize = view.intrinsicContentSize
        onAppear()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        onDisappear()
    }
}

private extension UIPreviewParameters {
    convenience init(backgroundColor: UIColor) {
        self.init()
        self.backgroundColor = backgroundColor
    }
}
