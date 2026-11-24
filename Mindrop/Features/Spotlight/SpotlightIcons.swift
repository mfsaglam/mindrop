import MapKit
import MindropCore
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Each category's icon as a PNG, which Spotlight shows on results in place of Mindrop's,
/// with Mindrop's as a small badge: the category's symbol in white on its colour, like a
/// Settings icon, so it reads on light and dark backgrounds alike.
enum SpotlightIcons {
    @MainActor
    static func make() -> [MemoryCategory: Data] {
        #if os(iOS)
        let size = CGSize(width: 120, height: 120)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let light = UITraitCollection(userInterfaceStyle: .light)
        let configuration = UIImage.SymbolConfiguration(pointSize: 56, weight: .semibold)
            .applying(UIImage.SymbolConfiguration(hierarchicalColor: .white))

        var icons: [MemoryCategory: Data] = [:]
        for category in MemoryCategory.allCases {
            guard let symbol = UIImage(systemName: category.symbolName, withConfiguration: configuration) else {
                continue
            }
            icons[category] = renderer.pngData { _ in
                UIColor(category.tint).resolvedColor(with: light).setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 27).fill()
                symbol.draw(at: CGPoint(
                    x: (size.width - symbol.size.width) / 2,
                    y: (size.height - symbol.size.height) / 2
                ))
            }
        }
        return icons
        #else
        var icons: [MemoryCategory: Data] = [:]
        for category in MemoryCategory.allCases {
            let renderer = ImageRenderer(content:
                RoundedRectangle(cornerRadius: 27)
                    .fill(category.tint)
                    .overlay {
                        Image(systemName: category.symbolName)
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 56, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 120, height: 120)
                    .environment(\.colorScheme, .light)
            )
            if let image = renderer.cgImage {
                icons[category] = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            }
        }
        return icons
        #endif
    }
}

#if DEBUG
/// Finds coordinates for an address, for the experiment that offers Spotlight's Directions
/// button. Goes through Apple Maps, so the address leaves the device: experiment only.
actor AddressLocator {
    static let shared = AddressLocator()

    /// Each address is looked up once per launch, found or not.
    private var cache: [String: SpotlightLocation?] = [:]

    func locate(_ address: String) async -> SpotlightLocation? {
        if let cached = cache[address] { return cached }
        let location = await Self.lookUp(address)
        cache[address] = location
        return location
    }

    @MainActor
    private static func lookUp(_ address: String) async -> SpotlightLocation? {
        guard let request = MKGeocodingRequest(addressString: address),
              let item = try? await request.mapItems.first
        else { return nil }
        let coordinate = item.location.coordinate
        return SpotlightLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
#endif
