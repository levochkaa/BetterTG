// UsernameSetupViewController.swift

import TDLibKit
import UIKit

// MARK: - UsernameSetupViewController

/// Telegram's UsernameSetupController for the account: the editable username with Telegram's format rules, a server
/// availability check (checkChatUsername) while typing, and Done to save it (setUsername). An empty field removes
/// the username.
final class UsernameSetupViewController: SettingsListViewController {
    private enum Status: Equatable {
        case idle
        case checking
        case available
        case invalid(String)
    }

    private static let checkDelay = Duration.milliseconds(300)

    private var userID: Int64?
    private var savedUsername = ""
    private var username = ""
    private var status = Status.idle
    private var isLoaded = false
    private var isSaving = false
    private var checkTask: Task<Void, Never>?

    deinit {
        checkTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Username.Title")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Done"), style: .prominent, target: self, action: #selector(donePressed),
        )
        navigationItem.rightBarButtonItem?.isEnabled = false
        load()
    }

    override func makeSections() -> [SettingsSection] {
        guard isLoaded else { return [] }
        var statusRows = [SettingsRow]()
        switch status {
        case .idle:
            break
        case .checking:
            statusRows.append(SettingsRow(
                title: L10n.telegram("Username.CheckingUsername"),
                style: .status(.secondaryLabel),
                accessory: .activity,
            ))
        case .available:
            statusRows.append(SettingsRow(
                title: L10n.telegram("Username.UsernameIsAvailable", username),
                style: .status(.systemGreen),
            ))
        case .invalid(let text):
            statusRows.append(SettingsRow(title: text, style: .status(.systemRed)))
        }
        var footer = L10n.telegram("Username.Help").withoutTelegramMarkup
        if !username.isEmpty, status == .idle || status == .available {
            footer += "\n\n" + L10n.telegram("Username.LinkHint", username)
                .withoutTelegramLinks
                .replacing("[", with: "")
                .replacing("]", with: "")
        }
        return [
            SettingsSection(header: L10n.telegram("Username.Username"), rows: [SettingsRow(
                title: "",
                style: .input(SettingsTextInput(
                    text: username,
                    placeholder: L10n.telegram("Username.Placeholder"),
                    prefix: "t.me/",
                    autocapitalization: .none,
                    autocorrection: false,
                ) { [weak self] text in self?.usernameChanged(text) }),
            )]),
            SettingsSection(footer: footer, rows: statusRows),
        ]
    }

    /// Telegram's checkAddressNameFormat.
    private static func formatError(_ value: String) -> String? {
        let characters = Array(value)
        for (index, character) in characters.enumerated() {
            if character == "_" {
                if index == 0 { return L10n.telegram("Username.InvalidStartsWithUnderscore") }
                if index == characters.count - 1 {
                    return characters.count < 4
                        ? L10n.telegram("Username.InvalidTooShort")
                        : L10n.telegram("Username.InvalidEndsWithUnderscore")
                }
            }
            if index == 0, character.isASCII, character.isNumber {
                return L10n.telegram("Username.InvalidStartsWithNumber")
            }
            let isAllowed = character == "_" || (character.isASCII && (character.isLetter || character.isNumber))
            if !isAllowed { return L10n.telegram("Username.InvalidCharacters") }
        }
        return characters.count < 4 ? L10n.telegram("Username.InvalidTooShort") : nil
    }

    private func load() {
        let client = client
        Task { [weak self] in
            guard let me = try? await client.getMe(), let self, contextIsCurrent else { return }
            userID = me.id
            savedUsername = me.usernames?.editableUsername ?? ""
            username = savedUsername
            isLoaded = true
            reload()
        }
    }

    private func usernameChanged(_ text: String) {
        username = text
        checkTask?.cancel()
        checkTask = nil
        if text == savedUsername || text.isEmpty {
            status = .idle
        } else if let formatError = Self.formatError(text) {
            status = .invalid(formatError)
        } else {
            status = .checking
            scheduleCheck(text)
        }
        updateStatus()
    }

    private func scheduleCheck(_ text: String) {
        guard let userID, contextIsCurrent else { return }
        let client = client
        checkTask = Task { [weak self] in
            try? await Task.sleep(for: Self.checkDelay)
            guard !Task.isCancelled else { return }
            let result = try? await client.send(TDNativeRequests.checkChatUsername(chatId: userID, username: text))
            guard let self, !Task.isCancelled, username == text else { return }
            status =
                switch result {
                case .checkChatUsernameResultOk: .available
                case .checkChatUsernameResultUsernameOccupied,
                     .checkChatUsernameResultUsernamePurchasable:
                    .invalid(L10n.telegram("Username.InvalidTaken"))
                case .checkChatUsernameResultPublicChatsTooMany:
                    .invalid(L10n.telegram("Username.TooManyPublicUsernamesError"))
                case .checkChatUsernameResultPublicGroupsUnavailable,
                     .checkChatUsernameResultUsernameInvalid,
                     nil:
                    .invalid(L10n.telegram("Username.InvalidValue"))
                }
            updateStatus()
        }
    }

    private func updateStatus() {
        reload(sections: IndexSet(integer: 1))
        let canSave = username != savedUsername && (username.isEmpty || status == .available)
        navigationItem.rightBarButtonItem?.isEnabled = canSave && !isSaving
    }

    @objc private func donePressed() {
        guard !isSaving, contextIsCurrent else { return }
        view.endEditing(true)
        isSaving = true
        updateStatus()
        let value = username
        let client = client
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.setUsername(username: value))
                guard let self, contextIsCurrent else { return }
                navigationController?.popViewController(animated: true)
            } catch {
                guard let self else { return }
                isSaving = false
                let message = (error as? TDLibError)?.message ?? ""
                if message.contains("OCCUPIED") {
                    status = .invalid(L10n.telegram("Username.InvalidTaken"))
                    updateStatus()
                } else {
                    updateStatus()
                    if contextIsCurrent { presentChatListActionFailure() }
                }
            }
        }
    }
}
