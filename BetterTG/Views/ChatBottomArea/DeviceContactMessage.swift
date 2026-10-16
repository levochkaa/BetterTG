// DeviceContactMessage.swift

import Contacts
import TDLibKit

// MARK: - DeviceContactMessage

/// Telegram's attachment menu Contact for device contacts (ChatControllerOpenAttachmentMenu, DeviceContactData): the
/// first phone number with the given and family names, and a vCard only for a single contact with more than a name
/// and one number (`isPrimitive`). Several picked contacts go out without vCards, as Telegram sends them.
enum DeviceContactMessage {
    // MARK: Internal

    /// The contacts as messages; a contact without a phone number is skipped.
    static func contents(for contacts: [CNContact]) -> [InputMessageContent] {
        let includesVCard = contacts.count == 1
        return contacts.compactMap { content(for: $0, includesVCard: includesVCard) }
    }

    // MARK: Private

    private static func content(for contact: CNContact, includesVCard: Bool) -> InputMessageContent? {
        let shared = sharedContact(from: contact)
        guard let phoneNumber = shared.phoneNumbers.first?.value.stringValue, !phoneNumber.isEmpty else { return nil }
        var firstName = shared.givenName
        let lastName = shared.familyName
        // TDLib refuses a contact without a first name; a company card is named by its organization.
        if firstName.isEmpty, lastName.isEmpty {
            firstName = shared.organizationName.isEmpty ? phoneNumber : shared.organizationName
        }
        let vcard = includesVCard && !isPrimitive(shared) ? serializedVCard(shared) : ""
        return .inputMessageContact(TDNativeInputMessageContact(contact: TDNativeContact(
            phoneNumber: phoneNumber,
            firstName: firstName,
            lastName: lastName,
            vcard: vcard,
            userId: 0,
        )))
    }

    /// DeviceContactExtendedData(contact:) followed by asMutableCNContact(): the fields Telegram shares, read only
    /// where the picker fetched them, so serializing never touches a missing key.
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

    /// DeviceContactExtendedData's isPrimitive: one number at most and nothing beyond the name.
    private static func isPrimitive(_ contact: CNContact) -> Bool {
        contact.phoneNumbers.count <= 1
            && contact.organizationName.isEmpty
            && contact.jobTitle.isEmpty
            && contact.departmentName.isEmpty
            && contact.emailAddresses.isEmpty
            && contact.urlAddresses.isEmpty
            && contact.postalAddresses.isEmpty
            && contact.birthday?.date == nil
            && contact.socialProfiles.isEmpty
            && contact.instantMessageAddresses.isEmpty
    }

    /// DeviceContactExtendedData's serializedVCard; an empty vCard sends the contact without one.
    private static func serializedVCard(_ contact: CNContact) -> String {
        guard let data = try? CNContactVCardSerialization.data(with: [contact]) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
