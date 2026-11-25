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

    /// The SF Symbol used for this category in the app and in Spotlight.
    var symbolName: String {
        switch self {
        case .network: "wifi"
        case .account: "key.fill"
        case .code: "lock.circle.fill"
        case .finance: "banknote.fill"
        case .contact: "phone.fill"
        case .people: "person.2.fill"
        case .address: "mappin.circle.fill"
        case .home: "house.fill"
        case .vehicle: "car.fill"
        case .document: "doc.text.fill"
        case .health: "cross.case.fill"
        case .link: "link"
        case .other: "square.grid.2x2.fill"
        }
    }

    /// For a memory without a category.
    static let uncategorisedSymbolName = "tag"

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

    /// The name and symbol in a menu or picker.
    var menuLabel: some View {
        Label { Text(title) } icon: { Image(systemName: symbolName) }
    }

    /// The icon carries the colour; the name stays in the text colour, so it reads well
    /// whatever the tint.
    var label: some View {
        Label { Text(title) } icon: {
            Image(systemName: symbolName)
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

extension Color {
    /// Keep white labels on medium tints and use black on pale fills.
    func contrastingForeground(in environment: EnvironmentValues) -> Color {
        let color = resolve(in: environment)
        let luminance = 0.2126 * color.linearRed + 0.7152 * color.linearGreen + 0.0722 * color.linearBlue
        return luminance >= 0.45 ? .black : .white
    }
}

/// The category's symbol on a rounded square of its colour. The symbol and category
/// palette also appear in Spotlight. A grey tag represents a memory without a category.
struct CategoryTile: View {
    let category: MemoryCategory?
    var size: CGFloat = 30

    @Environment(\.self) private var environment

    var body: some View {
        let background = category?.tint ?? .gray
        Image(systemName: category?.symbolName ?? MemoryCategory.uncategorisedSymbolName)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(background.contrastingForeground(in: environment))
            .frame(width: size, height: size)
            .background(background, in: .rect(cornerRadius: size * 0.225, style: .continuous))
            .accessibilityHidden(true)
    }
}
