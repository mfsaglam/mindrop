import MindropCore
import SwiftUI

extension MemoryCategory {
    /// `LocalizedStringResource`, so each name is extracted into the string catalog.
    var title: LocalizedStringResource {
        switch self {
        case .network: "Wi-Fi & Network"
        case .account: "Accounts"
        case .code: "Codes & PINs"
        case .finance: "Banking"
        case .contact: "Contacts"
        case .people: "Family & People"
        case .address: "Places"
        case .home: "Home & Devices"
        case .vehicle: "Vehicles"
        case .document: "IDs & Documents"
        case .health: "Health"
        case .link: "Links"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .network: "wifi"
        case .account: "person.badge.key"
        case .code: "lock.circle"
        case .finance: "banknote"
        case .contact: "phone"
        case .people: "person.2"
        case .address: "mappin.and.ellipse"
        case .home: "house"
        case .vehicle: "car"
        case .document: "doc.text"
        case .health: "cross.case"
        case .link: "link"
        case .other: "square.grid.2x2"
        }
    }

    /// One system colour per category, all thirteen distinct, so a category can be told
    /// apart at a glance. System colours adapt to light and dark mode on their own.
    var tint: Color {
        switch self {
        case .network: .blue
        case .account: .indigo
        case .code: .purple
        case .finance: .green
        case .contact: .teal
        case .people: .pink
        case .address: .orange
        case .home: .brown
        case .vehicle: .cyan
        case .document: .yellow
        case .health: .red
        case .link: .mint
        case .other: .gray
        }
    }

    /// The icon carries the colour; the name stays in the text colour, so it reads well
    /// whatever the tint.
    var label: some View {
        Label { Text(title) } icon: { Image(systemName: symbolName).foregroundStyle(tint) }
    }
}
