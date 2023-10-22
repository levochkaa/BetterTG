// CustomTextField.swift

import SwiftUI
import UniformTypeIdentifiers

private var isPastingText = false

private class CustomUITextView: UITextView {
    // swiftlint:disable:next function_body_length
    override func editMenu(for textRange: UITextRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let textInRange = self.text(in: textRange), !textInRange.isEmpty else {
            return UIMenu(children: suggestedActions)
        }
        
        let formatMenu = UIMenu(title: "Format", children: [
            UIAction(title: "Bold") { [weak self] _ in
                guard let self else { return }
                textStorage.addAttribute(.font, value: UIFont.bold, range: selectedRange)
                delegate?.textViewDidChange?(self)
            },
            UIAction(title: "Italic") { [weak self] _ in
                guard let self else { return }
                textStorage.addAttribute(.font, value: UIFont.italic, range: selectedRange)
                delegate?.textViewDidChange?(self)
            },
            UIAction(title: "Monospace") { [weak self] _ in
                guard let self else { return }
                textStorage.addAttribute(.font, value: UIFont.monospaced, range: selectedRange)
                delegate?.textViewDidChange?(self)
            },
            UIAction(title: "Link") { [weak self] _ in
                guard let self else { return }
                let alert = UIAlertController(title: "Enter URL", message: nil, preferredStyle: .alert)
                alert.addTextField { textField in
                    textField.placeholder = "https://google.com/"
                }
                alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert, weak self] _ in
                    guard let self, let text = alert?.textFields?.first?.text else { return }
                    textStorage.addAttribute(.link, value: URL(string: text)!, range: selectedRange)
                    delegate?.textViewDidChange?(self)
                })
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                UIApplication.currentKeyWindow?.rootViewController?.present(alert, animated: true)
            },
            UIAction(title: "Strikethrough") { [weak self] _ in
                guard let self else { return }
                textStorage.addAttribute(.strikethroughStyle, value: 1, range: selectedRange)
                delegate?.textViewDidChange?(self)
            },
            UIAction(title: "Underline") { [weak self] _ in
                guard let self else { return }
                textStorage.addAttribute(.underlineStyle, value: 1, range: selectedRange)
                delegate?.textViewDidChange?(self)
            },
            UIAction(title: "Spoiler") { [weak self] _ in
                guard let self else { return }
                textStorage.addAttribute(.backgroundColor, value: UIColor.gray, range: selectedRange)
                delegate?.textViewDidChange?(self)
            }
        ])
        
        var actions = suggestedActions
        actions.insert(formatMenu, at: 1)
        
        return UIMenu(children: actions)
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            return UIPasteboard.general.hasImages
        } else if action == #selector(captureTextFromCamera) {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }
    
    override func paste(_ sender: Any?) {
        if let images = UIPasteboard.general.images {
            nc.post(name: .localPasteImages, object: images.compactMap { writeImage($0) })
        } else {
            isPastingText = true
        }
        super.paste(sender)
    }
}

private struct UITextViewWrapper: UIViewRepresentable {
    typealias UIViewType = CustomUITextView
    
    @Binding var text: AttributedString
    @Binding var calculatedHeight: CGFloat
    
    var becomeFirstResponer: Bool
    
    let textView = CustomUITextView()
    
    func makeUIView(context: Context) -> UIViewType {
        textView.delegate = context.coordinator
        textView.attributedText = NSMutableAttributedString(string: text.string, attributes: defaultAttributes())
        textView.font = .body
        textView.isEditable = true
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.typingAttributes = defaultAttributes()
        
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        if becomeFirstResponer {
            textView.becomeFirstResponder()
        }
        
        return textView
    }
    
    func updateUIView(_ uiView: UIViewType, context: Context) {
        if AttributedString(uiView.attributedText) != text {
            uiView.attributedText = NSAttributedString(text)
        }
        recalculateHeight(view: uiView)
    }
    
    func recalculateHeight(view: UIView) {
        let newSize = view.sizeThatFits(CGSize(width: view.frame.size.width, height: .greatestFiniteMagnitude))
        let newCalculatedHeight = min(newSize.height, 302)
        if calculatedHeight != newCalculatedHeight {
            DispatchQueue.main.async {
                textView.isScrollEnabled = newCalculatedHeight == 302
                calculatedHeight = newCalculatedHeight
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    final class Coordinator: NSObject, UITextViewDelegate {
        
        let parent: UITextViewWrapper
        
        init(parent: UITextViewWrapper) {
            self.parent = parent
        }
        
        func textViewDidChange(_ uiView: UITextView) {
            parent.text = AttributedString(uiView.attributedText)
            parent.recalculateHeight(view: uiView)
        }
        
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            textView.typingAttributes = defaultAttributes()
            
            if isPastingText {
                if let item = UIPasteboard.general.items.first,
                   let data = (item[UTType.rtf.identifier] as? String)?.data(using: .utf8),
                   let attributedString = try? NSAttributedString(data: data, documentAttributes: nil) {
                    let mutableAttributedString = NSMutableAttributedString(attributedString: textView.attributedText)
                    mutableAttributedString.replaceCharacters(in: range, with: attributedString)
                    textView.attributedText = mutableAttributedString
                    textView.delegate?.textViewDidChange?(textView)
                    return false
                }
                isPastingText = false
            }
            
            return true
        }
    }
}

struct CustomTextField: View {
    
    private var placeholder: String
    @Binding private var text: AttributedString
    private var focus: Bool
    
    @State private var dynamicHeight: CGFloat = 38
    @State private var showingPlaceholder = true
    
    init(_ placeholder: String = "", text: Binding<AttributedString>, focus: Bool = false) {
        self.focus = focus
        self.placeholder = placeholder
        self._text = text
        self._showingPlaceholder = State(initialValue: self.text.characters.isEmpty)
    }
    
    var body: some View {
        UITextViewWrapper(text: $text, calculatedHeight: $dynamicHeight, becomeFirstResponer: focus)
            .frame(height: dynamicHeight)
            .onChange(of: text) { _, newText in
                showingPlaceholder = newText.characters.isEmpty
            }
            .background(alignment: .topLeading) {
                if showingPlaceholder {
                    Text(placeholder)
                        .foregroundStyle(.gray)
                        .padding(.leading, 4)
                        .padding(.top, 8)
                }
            }
    }
}
