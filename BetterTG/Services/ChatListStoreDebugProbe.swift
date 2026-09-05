// ChatListStoreDebugProbe.swift

#if DEBUG
    import Foundation
    import TDLibKit

    @MainActor enum ChatListStoreDebugProbe {
        private static var didRun = false

        static func runIfRequested(seed: CustomChat) {
            guard !didRun, ProcessInfo.processInfo.arguments.contains("-chat-list-store-probe") else { return }
            didRun = true
            let store = TelegramChatListStore()
            let account = UUID()
            func consume(_ update: Update) { store.consume(update, accountID: account, clientID: 1) }
            switch seed.type {
            case .bot(let user), .user(let user):
                consume(.updateUser(TDNativeUpdateUser(user: user)))
            case .group(let group):
                consume(.updateBasicGroup(TDNativeUpdateBasicGroup(basicGroup: group)))
            case .supergroup(let group):
                consume(.updateSupergroup(TDNativeUpdateSupergroup(supergroup: group)))
            }
            let main = ChatList.chatListMain
            let archive = ChatList.chatListArchive
            let folder = ChatList.chatListFolder(ChatListFolder(chatFolderId: 999))
            func position(_ list: ChatList, _ order: Int64) -> ChatPosition {
                ChatPosition(isPinned: false, list: list, order: order, source: nil)
            }
            var record = ChatListRecord(seed.chat)
            record.id = 1001
            record.positions = [position(main, 100), position(folder, 300)]
            let retainedSnapshot = record.snapshot
            consume(.updateNewChat(TDNativeUpdateNewChat(chat: retainedSnapshot)))
            record.id = 1002
            record.positions = [position(main, 100)]
            consume(.updateNewChat(TDNativeUpdateNewChat(chat: record.snapshot)))
            var checks = [String: Bool]()
            checks["descending_order_and_id_tie_break"] = store.chatIDs(in: main) == [1002, 1001]
            checks["independent_folder_membership"] = store.chatIDs(in: folder) == [1001]
            consume(.updateChatPosition(TDNativeUpdateChatPosition(chatId: 1002, position: position(main, 0))))
            checks["zero_order_removes_chat"] = store.chatIDs(in: main) == [1001]
            consume(.updateChatLastMessage(TDNativeUpdateChatLastMessage(
                chatId: 1001, lastMessage: nil, positions: [position(archive, 99)],
            )))
            checks["last_message_replaces_all_positions"] = store.chatIDs(in: main).isEmpty
                && store.chatIDs(in: folder).isEmpty && store.chatIDs(in: archive) == [1001]
            consume(.updateChatDraftMessage(TDNativeUpdateChatDraftMessage(
                chatId: 1002, draftMessage: nil, positions: [position(main, 200)],
            )))
            checks["draft_can_reinsert_chat"] = store.chatIDs(in: main) == [1002]
            consume(.updateChatReadInbox(TDNativeUpdateChatReadInbox(
                chatId: 1002, lastReadInboxMessageId: 77, unreadCount: 7,
            )))
            consume(.updateChatReadOutbox(TDNativeUpdateChatReadOutbox(chatId: 1002, lastReadOutboxMessageId: 88)))
            consume(.updateChatIsMarkedAsUnread(TDNativeUpdateChatIsMarkedAsUnread(
                chatId: 1002,
                isMarkedAsUnread: true,
            )))
            consume(.updateChatTitle(TDNativeUpdateChatTitle(chatId: 1002, title: "Updated")))
            let updated = store.customChat(id: 1002, in: main)
            checks["partial_updates_preserve_position_and_read_state"] = updated?.position.order == 200
                && updated?.unreadCount == 7 && updated?.chat.lastReadOutboxMessageId == 88
                && updated?.chat.isMarkedAsUnread == true && updated?.chat.title == "Updated"
            checks["native_snapshot_is_retained_and_reusable"] = retainedSnapshot.id == 1001
                && retainedSnapshot.positions.count == 2 && store.customChat(id: 1002, in: main)?.chat.id == 1002
            store.consume(
                .updateChatReadOutbox(TDNativeUpdateChatReadOutbox(chatId: 1002, lastReadOutboxMessageId: 99)),
                accountID: account,
                clientID: 2,
            )
            checks["client_restart_discards_old_cache"] = store.chatIDs(in: main).isEmpty && store.chatIDs(in: archive)
                .isEmpty
            store.consume(.updateNewChat(TDNativeUpdateNewChat(chat: record.snapshot)), accountID: UUID(), clientID: 3)
            checks["account_switch_does_not_reuse_peer_cache"] = store.customChat(id: 1002, in: main) == nil
            let passed = checks.values.allSatisfy(\.self)
            let proof = ([passed ? "PASS chat-list-store" : "FAIL chat-list-store"]
                + checks.keys.sorted().map { "\($0)=\(checks[$0] == true)" }).joined(separator: "\n")
            log(proof)
            if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? proof.write(
                    to: documents.appendingPathComponent("chat-list-store-probe.txt"),
                    atomically: true,
                    encoding: .utf8,
                )
            }
            assert(passed, proof)
        }
    }
#endif
