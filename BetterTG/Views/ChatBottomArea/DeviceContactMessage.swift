// DeviceContactMessage.swift

import Contacts
import TDLibKit

// MARK: - DeviceContactEntry

/// A phonebook person with a phone number, DeviceContactDataManager's basic data: the names and the numbers the
/// contact list shows, matches and sends without a vCard.
struct DeviceContactEntry {
    let identifier: String
    let firstName: String
    let lastName: String
    let organization: String
    let phoneNumbers: [String]
    /// DeviceContactDataManager's telegramReferences: the Telegram user the card's "Telegram" URL names, which Telegram
    /// writes when it saves a user to the phonebook. The contact list treats such a card as that user.
    let telegramUserID: Int64?

    /// The names, else the organization, else the first number.
    var title: String {
        DeviceContactMessage.displayName(firstName: firstName, lastName: lastName, organization: organization)
            ?? phoneNumbers.first ?? ""
    }
}

// MARK: - DeviceContactMessage

/// Telegram's contact messages (ChatControllerOpenAttachmentMenu, DeviceContactData): the first phone number with the
/// given and family names, and a vCard only for a single contact with more than a name and one number
/// (`isPrimitive`), after DeviceContactInfoController has let the user pick its fields. Several picked contacts go out
/// without vCards, as Telegram sends them.
enum DeviceContactMessage {
    // MARK: Internal

    /// DeviceContactData's phonebookUsernamePrefix: "https://t.me/" and phonebookUsernamePathPrefix.
    private static let telegramReferencePrefix = "https://t.me/@id"

    /// TDLib's contact: a Telegram user goes with its user ID. TDLib refuses a contact without a first name, so a
    /// company
    /// card is named by its organization and a nameless one by its number.
    static func content(
        phoneNumber: String,
        firstName: String,
        lastName: String,
        organization: String,
        vcard: String,
        userID: Int64,
    ) -> InputMessageContent {
        var firstName = firstName
        if firstName.isEmpty, lastName.isEmpty {
            firstName = organization.isEmpty ? phoneNumber : organization
        }
        return .inputMessageContact(TDNativeInputMessageContact(contact: TDNativeContact(
            phoneNumber: phoneNumber,
            firstName: firstName,
            lastName: lastName,
            vcard: vcard,
            userId: userID,
        )))
    }

    /// The contact's first number and names, with its vCard when asked; nil without a number.
    static func content(for contact: CNContact, userID: Int64, includesVCard: Bool) -> InputMessageContent? {
        guard let phoneNumber = contact.phoneNumbers.first?.value.stringValue, !phoneNumber.isEmpty else { return nil }
        return content(
            phoneNumber: phoneNumber,
            firstName: contact.givenName,
            lastName: contact.familyName,
            organization: contact.organizationName,
            vcard: includesVCard ? serializedVCard(contact) : "",
            userID: userID,
        )
    }

    /// DeviceContactDataManager's basic data: the phonebook's people with a phone number, by name. Blocks while the
    /// store reads, so it runs off the main thread. The URLs come along for the cards' Telegram references.
    static func phonebookContacts() -> [DeviceContactEntry] {
        let keys = [
            CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactPhoneNumbersKey,
            CNContactUrlAddressesKey,
        ] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = true
        var entries = [DeviceContactEntry]()
        try? CNContactStore().enumerateContacts(with: request) { contact, _ in
            let phoneNumbers = contact.phoneNumbers.map(\.value.stringValue).filter { !$0.isEmpty }
            guard !phoneNumbers.isEmpty else { return }
            let referencedUserID = contact.urlAddresses
                .lazy
                .filter { $0.label == "Telegram" }
                .compactMap { Self.telegramUserID(reference: $0.value as String) }
                .first
            entries.append(DeviceContactEntry(
                identifier: contact.identifier,
                firstName: contact.givenName,
                lastName: contact.familyName,
                organization: contact.organizationName,
                phoneNumbers: phoneNumbers,
                telegramUserID: referencedUserID,
            ))
        }
        return entries.sorted { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    /// DeviceContactData's parseAppSpecificContactReference: the user ID in a "https://t.me/@id<ID>" URL.
    static func telegramUserID(reference value: String) -> Int64? {
        guard value.hasPrefix(telegramReferencePrefix) else { return nil }
        return Int64(value.dropFirst(telegramReferencePrefix.count))
    }

    /// DeviceContactDataManager's extended data for one contact, as a contact Telegram can share.
    static func extendedContact(identifier: String) -> CNMutableContact? {
        let keys = [
            CNContactGivenNameKey, CNContactFamilyNameKey, CNContactMiddleNameKey, CNContactNamePrefixKey,
            CNContactNameSuffixKey, CNContactPhoneNumbersKey, CNContactOrganizationNameKey, CNContactJobTitleKey,
            CNContactDepartmentNameKey, CNContactEmailAddressesKey, CNContactUrlAddressesKey,
            CNContactPostalAddressesKey, CNContactBirthdayKey, CNContactSocialProfilesKey,
            CNContactInstantMessageAddressesKey,
        ] as [CNKeyDescriptor]
        guard let contact = try? CNContactStore().unifiedContact(withIdentifier: identifier, keysToFetch: keys) else {
            return nil
        }
        return sharedContact(from: contact)
    }

    /// DeviceContactExtendedData(user:): a Telegram user's names and number, labelled mobile.
    static func basicContact(firstName: String, lastName: String, phoneNumber: String) -> CNMutableContact {
        let contact = CNMutableContact()
        contact.givenName = firstName
        contact.familyName = lastName
        contact.phoneNumbers = [CNLabeledValue(
            label: CNLabelPhoneNumberMobile,
            value: CNPhoneNumber(stringValue: phoneNumber),
        )]
        return contact
    }

    /// DeviceContactExtendedData's isPrimitive: one number at most and nothing beyond the name.
    static func isPrimitive(_ contact: CNContact) -> Bool {
        contact.phoneNumbers.count <= 1
            && contact.organizationName.isEmpty
            && contact.jobTitle.isEmpty
            && contact.departmentName.isEmpty
            && contact.emailAddresses.isEmpty
            && contact.urlAddresses.isEmpty
            && contact.postalAddresses.isEmpty
            && birthdayDate(contact) == nil
            && contact.socialProfiles.isEmpty
            && contact.instantMessageAddresses.isEmpty
    }

    /// DeviceContactExtendedData's birthdayDate: the card's birthday as a day, in the Gregorian calendar when the card
    /// doesn't name one.
    static func birthdayDate(_ contact: CNContact) -> Foundation.Date? {
        guard let birthday = contact.birthday else { return nil }
        return birthday.date ?? Calendar(identifier: .gregorian).date(from: birthday)
    }

    /// The digits of a number, as Telegram's DeviceContactNormalizedPhoneNumber compares a phonebook entry with a user.
    static func normalizedPhoneNumber(_ phoneNumber: String) -> String {
        String(phoneNumber.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) })
    }

    /// The names, else the organization; nil for a card with neither.
    static func displayName(firstName: String, lastName: String, organization: String) -> String? {
        let name = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        if !name.isEmpty { return name }
        return organization.isEmpty ? nil : organization
    }

    /// Telegram's localizedPhoneNumberLabel (ContactInfoStrings).
    static func phoneLabel(_ label: String?) -> String {
        guard let label, !label.isEmpty else { return L10n.telegram("ContactInfo.PhoneLabelMain") }
        if label == "X-iPhone" { return "iPhone" }
        return CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: label)
    }

    /// Telegram's localizedGenericContactFieldLabel (ContactInfoStrings).
    static func fieldLabel(_ label: String?) -> String {
        guard let label, !label.isEmpty else { return L10n.telegram("ContactInfo.PhoneLabelMain") }
        return CNLabeledValue<NSString>.localizedString(forLabel: label)
    }

    /// DeviceContactExtendedData's serializedVCard; an empty vCard sends the contact without one.
    static func serializedVCard(_ contact: CNContact) -> String {
        guard let data = try? CNContactVCardSerialization.data(with: [contact]) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: Private

    /// DeviceContactExtendedData(contact:) followed by asMutableCNContact(): the fields Telegram shares, read only
    /// where they were fetched, so serializing never touches a missing key.
    private static func sharedContact(from contact: CNContact) -> CNMutableContact {
        let shared = CNMutableContact()
        func copy(_ key: String, _ apply: () -> Void) {
            if contact.isKeyAvailable(key) { apply() }
        }
        copy(CNContactGivenNameKey) { shared.givenName = contact.givenName }
        copy(CNContactFamilyNameKey) { shared.familyName = contact.familyName }
        copy(CNContactMiddleNameKey) { shared.middleName = contact.middleName }
        copy(CNContactNamePrefixKey) { shared.namePrefix = contact.namePrefix }
        copy(CNContactNameSuffixKey) { shared.nameSuffix = contact.nameSuffix }
        copy(CNContactPhoneNumbersKey) { shared.phoneNumbers = contact.phoneNumbers }
        copy(CNContactOrganizationNameKey) { shared.organizationName = contact.organizationName }
        copy(CNContactJobTitleKey) { shared.jobTitle = contact.jobTitle }
        copy(CNContactDepartmentNameKey) { shared.departmentName = contact.departmentName }
        copy(CNContactEmailAddressesKey) { shared.emailAddresses = contact.emailAddresses }
        copy(CNContactUrlAddressesKey) { shared.urlAddresses = contact.urlAddresses }
        copy(CNContactPostalAddressesKey) { shared.postalAddresses = contact.postalAddresses }
        copy(CNContactBirthdayKey) { shared.birthday = contact.birthday }
        copy(CNContactSocialProfilesKey) { shared.socialProfiles = contact.socialProfiles }
        copy(CNContactInstantMessageAddressesKey) { shared.instantMessageAddresses = contact.instantMessageAddresses }
        return shared
    }
}
