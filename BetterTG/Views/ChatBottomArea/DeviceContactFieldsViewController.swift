// DeviceContactFieldsViewController.swift

import Contacts
import TDLibKit
import UIKit

// MARK: - DeviceContactFieldsViewController

/// Telegram's DeviceContactInfoController in its `.filter` mode, which the attachment menu opens for one contact with
/// more than a name and a number: the card's name and job, then every phone, email, URL, address, birthday, social
/// profile and messenger with a check circle, all checked at first. Send shares the checked fields in the vCard
/// (filteredContactData) and stays off while no phone is checked.
final class DeviceContactFieldsViewController: SettingsListViewController {
    // MARK: Private

    /// DeviceContactInfoDataId: a field by its kind and place on the card.
    private enum Field: Hashable {
        case phone(Int)
        case email(Int)
        case url(Int)
        case address(Int)
        case birthday
        case socialProfile(Int)
        case instantMessenger(Int)
    }

    // MARK: Internal

    /// Called once the card has gone after Close or Send; a swipe down reaches the presenter's delegate.
    var onDismiss: (() -> Void)?

    private let contact: CNContact
    private let avatarID: String
    private let peer: SettingsPeer?
    private let userID: Int64
    private let send: (InputMessageContent) -> Void
    /// DeviceContactInfoState's excludedComponents: the fields the user has unchecked.
    private var excluded = Set<Field>()
    /// The phones by their place on the card, once TDLib has put them in their country's mask.
    private var formattedNumbers = [Int: String]()
    private var didFinish = false

    private lazy var sendItem = UIBarButtonItem(
        title: L10n.telegram("ShareMenu.Send"),
        style: .prominent,
        target: self,
        action: #selector(sendPressed),
    )

    /// `avatarID` keeps a phonebook card's avatar colour as the contact list shows it; `peer` is the Telegram user the
    /// card belongs to.
    init(
        contact: CNContact,
        avatarID: String,
        peer: SettingsPeer?,
        userID: Int64,
        send: @escaping (InputMessageContent) -> Void,
    ) {
        self.contact = contact
        self.avatarID = avatarID
        self.peer = peer
        self.userID = userID
        self.send = send
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("UserInfo.Title")
        let closeItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(closePressed),
        )
        closeItem.accessibilityLabel = L10n.telegram("Common.Close")
        navigationItem.leftBarButtonItem = closeItem
        navigationItem.rightBarButtonItem = sendItem
        updateSendItem()
        formatPhoneNumbers()
    }

    /// ItemListTextWithLabelItem: the field's label above in the primary colour, its value below in the accent colour.
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        guard let row = settingsRow(at: indexPath), case .subtitle = row.style,
              var configuration = cell.contentConfiguration as? UIListContentConfiguration
        else { return cell }
        configuration.textProperties.font = .preferredFont(forTextStyle: .subheadline)
        configuration.textProperties.color = .label
        configuration.secondaryTextProperties.font = .preferredFont(forTextStyle: .body)
        configuration.secondaryTextProperties.color = .tintColor
        cell.contentConfiguration = configuration
        return cell
    }

    /// deviceContactInfoEntries with `selecting`: the info row, then the fields in Telegram's order. Telegram's note
    /// row never shows, since DeviceContactExtendedData(contact:) always leaves the note empty.
    override func makeSections() -> [SettingsSection] {
        var fields = [SettingsRow]()
        for (index, number) in contact.phoneNumbers.enumerated() {
            fields.append(fieldRow(
                .phone(index),
                label: DeviceContactMessage.phoneLabel(number.label),
                value: formattedNumbers[index] ?? Self.displayedPhoneNumber(number.value.stringValue),
            ))
        }
        for (index, email) in contact.emailAddresses.enumerated() {
            fields.append(fieldRow(
                .email(index),
                label: DeviceContactMessage.fieldLabel(email.label),
                value: email.value as String,
            ))
        }
        for (index, url) in contact.urlAddresses.enumerated() {
            fields.append(fieldRow(
                .url(index),
                label: DeviceContactMessage.fieldLabel(url.label),
                value: url.value as String,
            ))
        }
        for (index, address) in contact.postalAddresses.enumerated() {
            let value = address.value
            let text = [value.street, value.state, value.city, value.country, value.postalCode]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            fields.append(fieldRow(.address(index), label: DeviceContactMessage.fieldLabel(address.label), value: text))
        }
        if let birthday = DeviceContactMessage.birthdayDate(contact) {
            fields.append(fieldRow(
                .birthday,
                label: L10n.telegram("ContactInfo.BirthdayLabel"),
                value: Self.birthdayText(birthday),
            ))
        }
        for (index, profile) in contact.socialProfiles.enumerated() {
            var label = DeviceContactMessage.fieldLabel(profile.label)
            var text = profile.value.username
            switch profile.value.service.lowercased() {
            case "twitter":
                label = "Twitter"
                text = "@\(profile.value.username)"
            case "facebook":
                label = "Facebook"
            default:
                if !profile.value.service.isEmpty { label = profile.value.service }
            }
            fields.append(fieldRow(.socialProfile(index), label: label, value: text))
        }
        for (index, messenger) in contact.instantMessageAddresses.enumerated() {
            let service = messenger.value.service
            fields.append(fieldRow(
                .instantMessenger(index),
                label: service.isEmpty ? DeviceContactMessage.fieldLabel(messenger.label) : service,
                value: messenger.value.username,
            ))
        }
        var result = [SettingsSection(rows: [infoRow()])]
        if !fields.isEmpty { result.append(SettingsSection(rows: fields)) }
        return result
    }

    /// The phone until TDLib answers, or when it knows no country for it: a Telegram user's number, which comes
    /// without the plus, gets one; a phonebook number stays as typed.
    private static func displayedPhoneNumber(_ value: String) -> String {
        guard !value.isEmpty, DeviceContactMessage.normalizedPhoneNumber(value) == value else { return value }
        return "+" + value
    }

    /// Telegram's stringForDate, or stringForDateWithoutYear for a birthday saved without its year.
    private static func birthdayText(_ date: Foundation.Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .none
        formatter.timeZone = Foundation.TimeZone.current
        let year = Calendar(identifier: .gregorian).dateComponents([.era, .year, .month, .day], from: date).year
        if let year, year > 1 {
            formatter.dateStyle = .medium
        } else {
            formatter.setLocalizedDateFormatFromTemplate("MMMMd")
        }
        return formatter.string(from: date)
    }

    /// deviceContactInfoEntries shows every phone through formatPhoneNumber(number.value): read as international and
    /// put in its country's mask.
    private func formatPhoneNumbers() {
        let client = client
        let numbers = contact.phoneNumbers.map(\.value.stringValue)
        Task { [weak self] in
            var formatted = [Int: String]()
            for (index, number) in numbers.enumerated() {
                if let value = await PhoneNumberFormat.international(number, client: client) {
                    formatted[index] = value
                }
            }
            guard let self, !formatted.isEmpty else { return }
            formattedNumbers = formatted
            reload()
        }
    }

    // MARK: Rows

    /// The info entry: the Telegram user, else the card as a person named by its names, an organization-only card by
    /// its organization and a nameless one "Contact"; the job summary under it, except for an organization.
    private func infoRow() -> SettingsRow {
        let organization = contact.organizationName
        let isOrganization = contact.givenName.isEmpty && contact.familyName.isEmpty && !organization.isEmpty
        var firstName = isOrganization ? organization : contact.givenName
        if firstName.isEmpty { firstName = L10n.telegram("Message.Contact") }
        let lastName = isOrganization ? "" : contact.familyName
        let shownPeer = peer ?? SettingsPeer.deviceContact(
            identifier: avatarID,
            title: [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " "),
            firstName: firstName,
            lastName: lastName,
        )
        let job = [organization, contact.departmentName, contact.jobTitle]
            .filter { !$0.isEmpty }
            .joined(separator: " — ")
        return SettingsRow(
            title: shownPeer.title,
            detail: isOrganization || job.isEmpty ? nil : job,
            style: .peer(shownPeer),
        )
    }

    private func fieldRow(_ field: Field, label: String, value: String) -> SettingsRow {
        let isIncluded = !excluded.contains(field)
        return SettingsRow(
            title: label,
            detail: value,
            style: .subtitle,
            symbol: isIncluded ? "checkmark.circle.fill" : "circle",
            symbolTint: isIncluded ? .tintColor : .systemGray3,
        ) { [weak self] in
            self?.toggle(field)
        }
    }

    /// DeviceContactInfoController's toggleSelection.
    private func toggle(_ field: Field) {
        if excluded.remove(field) == nil { excluded.insert(field) }
        reload()
        updateSendItem()
    }

    private func updateSendItem() {
        sendItem.isEnabled = contact.phoneNumbers.indices.contains { !excluded.contains(.phone($0)) }
    }

    /// filteredContactData: the card without the unchecked fields; the names and the job always go.
    private func filteredContact() -> CNMutableContact? {
        guard let filtered = contact.mutableCopy() as? CNMutableContact else { return nil }
        filtered.phoneNumbers = kept(contact.phoneNumbers, Field.phone)
        filtered.emailAddresses = kept(contact.emailAddresses, Field.email)
        filtered.urlAddresses = kept(contact.urlAddresses, Field.url)
        filtered.postalAddresses = kept(contact.postalAddresses, Field.address)
        filtered.socialProfiles = kept(contact.socialProfiles, Field.socialProfile)
        filtered.instantMessageAddresses = kept(contact.instantMessageAddresses, Field.instantMessenger)
        if excluded.contains(.birthday) { filtered.birthday = nil }
        return filtered
    }

    private func kept<Value>(_ values: [Value], _ field: (Int) -> Field) -> [Value] {
        values.enumerated().filter { !excluded.contains(field($0.offset)) }.map(\.element)
    }

    /// The filter completion in ChatControllerOpenAttachmentMenu: the first checked number, the names and the vCard,
    /// with the Telegram user's ID.
    @objc private func sendPressed() {
        guard !didFinish, let filtered = filteredContact(),
              let phoneNumber = filtered.phoneNumbers.first?.value.stringValue
        else { return }
        didFinish = true
        let content = DeviceContactMessage.content(
            phoneNumber: phoneNumber,
            firstName: filtered.givenName,
            lastName: filtered.familyName,
            organization: filtered.organizationName,
            vcard: DeviceContactMessage.serializedVCard(filtered),
            userID: userID,
        )
        let send = send
        let onDismiss = onDismiss
        dismiss(animated: true) {
            onDismiss?()
            send(content)
        }
    }

    @objc private func closePressed() {
        guard !didFinish else { return }
        didFinish = true
        let onDismiss = onDismiss
        dismiss(animated: true) { onDismiss?() }
    }
}
