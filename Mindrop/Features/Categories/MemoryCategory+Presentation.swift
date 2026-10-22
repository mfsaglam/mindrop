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

    /// The category's Iconsax symbol, in its Bulk style: drawn with
    /// `.symbolRenderingMode(.hierarchical)`, its soft parts take a lighter shade of the tint.
    var symbolName: String {
        switch self {
        case .network: "ix.wifi.bulk"
        case .account: "ix.key.bulk"
        case .code: "ix.lock-circle.bulk"
        case .finance: "ix.money.bulk"
        case .contact: "ix.call.bulk"
        case .people: "ix.profile-2user.bulk"
        case .address: "ix.location.bulk"
        case .home: "ix.home-2.bulk"
        case .vehicle: "ix.car.bulk"
        case .document: "ix.document-text.bulk"
        case .health: "ix.hospital.bulk"
        case .link: "ix.link.bulk"
        case .other: "ix.category.bulk"
        }
    }

    /// For a memory without a category.
    static let uncategorisedSymbolName = "ix.tag.bulk"

    /// The Linear version, for menus and pickers. iOS draws those in one colour, and Bulk's
    /// soft layer would then cover the detail drawn over it.
    var menuSymbolName: String {
        symbolName.replacingOccurrences(of: ".bulk", with: ".linear")
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

    /// White text on yellow is barely readable, so a button filled with it is labelled in
    /// black.
    var prefersDarkText: Bool {
        self == .document
    }

    /// The name with its Linear icon, as a row of a menu or picker.
    var menuLabel: some View {
        Label { Text(title) } icon: { Image(menuSymbolName) }
    }

    /// The icon carries the colour; the name stays in the text colour, so it reads well
    /// whatever the tint.
    var label: some View {
        Label { Text(title) } icon: {
            Image(symbolName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
    }
}

extension Glass {
    /// Regular glass with a touch of the category's colour: enough to tell cards apart, not
    /// so much that they read as coloured cards. Plain glass without a category.
    static func category(_ category: MemoryCategory?) -> Glass {
        guard let category else { return .regular }
        return .regular.tint(category.tint.opacity(0.08))
    }
}

/// The category's symbol, white on a rounded square of its colour: the icon each result
/// carries in Spotlight (`SpotlightIcons`), so the app and Spotlight look like one thing.
/// A grey tag without a category.
struct CategoryTile: View {
    let category: MemoryCategory?
    var size: CGFloat = 30

    var body: some View {
        Image(category?.symbolName ?? MemoryCategory.uncategorisedSymbolName)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(category?.tint ?? .gray, in: .rect(cornerRadius: size * 0.225, style: .continuous))
            .accessibilityHidden(true)
    }
}
