// SPDX-License-Identifier: MPL-2.0

import Contacts
import Foundation
import UIKit

/// Reads contacts from `CNContactStore` for the PC Contacts tab and Caller ID.
public final class IosContacts: @unchecked Sendable {
    public static let shared = IosContacts()

    private let store = CNContactStore()

    private init() {}

    public static func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            CNContactStore().requestAccess(for: .contacts) { granted, _ in
                cont.resume(returning: granted)
            }
        }
    }

    public static var isAuthorized: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        return status == .authorized
    }

    public func contacts(query: String?, offset: UInt32, limit: UInt32) -> [Contact] {
        guard Self.isAuthorized else { return [] }
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        ]

        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        let needle = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        var matched: [Contact] = []
        let skip = Int(offset)
        let maxItems = Int(max(1, min(limit, 250)))
        var seen = 0

        do {
            try store.enumerateContacts(with: request) { cnContact, stop in
                guard !cnContact.phoneNumbers.isEmpty else { return }
                let fullName = CNContactFormatter.string(from: cnContact, style: .fullName)
                    ?? ([cnContact.givenName, cnContact.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " "))
                let displayName = fullName.isEmpty ? cnContact.organizationName : fullName
                guard !displayName.isEmpty else { return }

                let numbers: [ContactNumber] = cnContact.phoneNumbers.map { labeled in
                    let label = labeled.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) }
                    return ContactNumber(number: labeled.value.stringValue, label: label)
                }

                if !needle.isEmpty {
                    let nameMatches = displayName.lowercased().contains(needle)
                    let numberMatches = numbers.contains { $0.number.lowercased().contains(needle) }
                    guard nameMatches || numberMatches else { return }
                }

                if seen < skip {
                    seen += 1
                    return
                }

                var avatarData: Data? = nil
                if let rawThumb = cnContact.thumbnailImageData,
                   let img = UIImage(data: rawThumb) {
                    avatarData = IosPhotos.compressJpeg(img, maxBytes: 16 * 1024)
                }

                matched.append(
                    Contact(
                        id: cnContact.identifier,
                        name: displayName,
                        numbers: numbers,
                        starred: false,
                        photo: avatarData
                    )
                )
                seen += 1
                if matched.count >= maxItems {
                    stop.pointee = true
                }
            }
        } catch {
            return []
        }

        return matched
    }
}
