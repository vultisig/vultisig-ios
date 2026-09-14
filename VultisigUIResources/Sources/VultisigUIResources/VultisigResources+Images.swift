import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension VultisigResources {
    /// Generated from the canonical catalog, including token, chain and UI artwork.
    public static let imageNames: Set<String> = {
        guard let url = bundle.url(forResource: "image-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let names = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(names)
    }()

    public static func containsImage(named name: String) -> Bool {
        imageNames.contains(name)
    }

    public static func image(named name: String) -> Image? {
        guard containsImage(named: name) else { return nil }
        return Image(name, bundle: bundle)
    }

    #if canImport(UIKit)
    public static func platformImage(named name: String) -> UIImage? {
        guard containsImage(named: name) else { return nil }
        return UIImage(named: name, in: bundle, compatibleWith: nil)
    }
    #elseif canImport(AppKit)
    public static func platformImage(named name: String) -> NSImage? {
        guard containsImage(named: name) else { return nil }
        return bundle.image(forResource: NSImage.Name(name))
    }
    #endif
}
