// MessageView.swift

import SwiftUI
import SwiftUIX
import TDLibKit

struct MessageView: View {
    
    @State var customMessage: CustomMessage
    @State var isContextMenu: Bool
    var focused: FocusState<Bool>.Binding?
    @Binding var openedMessageContextMenu: CustomMessage?
    @Binding var openedPhotoInfo: OpenedPhotoInfo?
    var rootNamespace: Namespace.ID?
    
    @EnvironmentObject var viewModel: ChatViewModel
    
    @State var recognized = false
    @State var recognizedText = "..."
    @State var isListeningVoiceNote = false
    @State var recognizeSpeech = false
    @Namespace var voiceNoteNamespace
    
    @State var isOutgoing = true
    
    @State var replyWidth: Double = 0
    @State var textWidth: Double = 0
    @State var contentWidth: Double = 0
    @State var editWidth: Double = 0
    
    @State var textSize: CGSize = .zero
    
    let recognizedTextId = "recognizedTextId"
    let playId = "playId"
    let currentTimeId = "currentTimeId"
    let durationId = "durationId"
    let chevronId = "chevronId"
    let speechId = "speechId"
    
    init(
        customMessage: CustomMessage,
        isContextMenu: Bool = false,
        focused: FocusState<Bool>.Binding? = nil,
        openedMessageContextMenu: Binding<CustomMessage?>? = nil,
        openedPhotoInfo: Binding<OpenedPhotoInfo?>? = nil,
        rootNamespace: Namespace.ID? = nil
    ) {
        self._customMessage = State(initialValue: customMessage)
        self._isContextMenu = State(initialValue: isContextMenu)
        self.focused = focused
        self.rootNamespace = rootNamespace
        
        if let openedMessageContextMenu {
            self._openedMessageContextMenu = Binding(projectedValue: openedMessageContextMenu)
        } else {
            self._openedMessageContextMenu = Binding(get: { nil }, set: { _ in })
        }
        
        if let openedPhotoInfo {
            self._openedPhotoInfo = Binding(projectedValue: openedPhotoInfo)
        } else {
            self._openedPhotoInfo = Binding(get: { nil }, set: { _ in })
        }
    }
    
    var body: some View {
        GestureButton {
            focused?.wrappedValue = false
        } longPressAction: {
            withAnimation {
                openedMessageContextMenu = customMessage
            }
        } doubleTapAction: {
            log("Double tap on message detected, reactions aren't implemented")
        } label: {
            ZStack(alignment: isOutgoing ? .bottomTrailing : .bottomLeading) {
                bodyView
                    .if(openedMessageContextMenu?.message.id == customMessage.message.id && !isContextMenu) {
                        $0.opacity(0)
                    }
                    // com.apple.SwiftUI.AsyncRenderer (23): EXC_BAD_ACCESS (code=2, address=0x16e2fb418)
                    // .if(rootNamespace != nil) {
                    //     $0.matchedGeometryEffect(id: customMessage.message.id, in: rootNamespace!)
                    // }
                    .anchorPreference(key: BoundsViewModelPreferenceKey.self, value: .bounds) {
                        [customMessage.message.id: BoundsAnchorWithChatViewModel(anchor: $0, chatViewModel: viewModel)]
                    }
                    .onAppear {
                        isOutgoing = customMessage.message.isOutgoing
                    }
                    .onReceive(nc.publisher(for: .messageEdited)) { notification in
                        guard let messageEdited = notification.object as? UpdateMessageEdited,
                              messageEdited.chatId == customMessage.message.chatId,
                              messageEdited.messageId == customMessage.message.id
                        else { return }
                        
                        Task {
                            guard let customMessage = await viewModel.getCustomMessage(fromId: messageEdited.messageId)
                            else { return }
                            
                            await MainActor.run {
                                withAnimation {
                                    self.customMessage = customMessage
                                }
                            }
                        }
                    }
                
                if isContextMenu {
                    customContextMenu
                        .offset(x: 0, y: contextMenuOffset(for: customMessage.message))
                }
            }
        }
    }
    
    @ViewBuilder var bodyView: some View {
        VStack(alignment: customMessage.message.isOutgoing ? .trailing : .leading, spacing: 1) {
            if customMessage.replyUser != nil, customMessage.replyToMessage != nil {
                ReplyMessageView(customMessage: customMessage, type: .replied)
                    .padding(5)
                    .background(backgroundColor(for: .reply))
                    .cornerRadius(corners(for: .reply), 15)
                    .readSize { replyWidth = $0.width }
            }
            
            messageContent
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .padding(1)
                .background(backgroundColor(for: .content))
                .cornerRadius(corners(for: .content), 15)
                .readSize { contentWidth = $0.width }
            
            messageText
                .multilineTextAlignment(.leading)
                .padding(8)
                .background(backgroundColor(for: .text))
                .cornerRadius(corners(for: .text), 15)
                .readSize { textWidth = $0.width }
            
            if customMessage.message.editDate != 0 {
                Text("edited")
                    .font(.caption)
                    .foregroundColor(.white).opacity(0.5)
                    .padding(3)
                    .background(backgroundColor(for: .edit))
                    .cornerRadius(corners(for: .edit), 15)
                    .readSize { editWidth = $0.width }
            }
        }
    }
    
    func backgroundColor(for type: MessagePart) -> Color {
        switch type {
            case .text, .content:
                if viewModel.highlightedMessageId == customMessage.message.id {
                    return .white.opacity(0.5)
                }
                fallthrough
            default:
                return customMessage.sendFailed ? .red : .gray6
        }
    }
    
    func contextMenuOffset(for msg: Message) -> CGFloat {
        var count: CGFloat = 0
        if msg.canBeEdited { count += 1 }
        if msg.canBeDeletedForAllUsers { count += 1 }
        if msg.canBeDeletedOnlyForSelf { count += 1 }
        if !msg.isChannelPost { count += 1 }
        return count * 40 + 10
    }
}
