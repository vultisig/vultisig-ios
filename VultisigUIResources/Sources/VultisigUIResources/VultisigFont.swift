import CoreText
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum VultisigFont: CaseIterable, Sendable {
    case brockmannBold
    case brockmannMedium
    case brockmannRegular
    case brockmannSemibold
    case satoshiMedium

    public var postScriptName: String {
        switch self {
        case .brockmannBold:
            "Brockmann-Bold"
        case .brockmannMedium:
            "Brockmann-Medium"
        case .brockmannRegular:
            "Brockmann-Regular"
        case .brockmannSemibold:
            "Brockmann-SemiBold"
        case .satoshiMedium:
            "Satoshi-Medium"
        }
    }

    public func font(size: CGFloat) -> Font {
        FontRegistrar.shared.register(resource)
        return .custom(postScriptName, size: size)
    }

    #if canImport(UIKit)
    public func uiFont(size: CGFloat) -> UIFont {
        FontRegistrar.shared.register(resource)
        return UIFont(name: postScriptName, size: size) ?? .systemFont(ofSize: size)
    }
    #endif

    #if canImport(AppKit)
    public func nsFont(size: CGFloat) -> NSFont {
        FontRegistrar.shared.register(resource)
        return NSFont(name: postScriptName, size: size) ?? .systemFont(ofSize: size)
    }
    #endif

    var resource: FontResource {
        switch self {
        case .brockmannBold:
            .init(name: "Brockmann-Bold", extension: "otf")
        case .brockmannMedium:
            .init(name: "Brockmann-Medium", extension: "otf")
        case .brockmannRegular:
            .init(name: "Brockmann-Regular", extension: "otf")
        case .brockmannSemibold:
            .init(name: "Brockmann-SemiBold", extension: "otf")
        case .satoshiMedium:
            .init(name: "Satoshi-Medium", extension: "otf")
        }
    }
}

struct FontResource: Hashable {
    let name: String
    let `extension`: String

    static let all: [FontResource] = [
        .init(name: "Brockmann-Bold", extension: "otf"),
        .init(name: "Brockmann-Medium", extension: "otf"),
        .init(name: "Brockmann-Regular", extension: "otf"),
        .init(name: "Brockmann-SemiBold", extension: "otf"),
        .init(name: "Montserrat-Italic", extension: "ttf"),
        .init(name: "Montserrat", extension: "ttf"),
        .init(name: "Satoshi-Medium", extension: "otf")
    ]
}

final class FontRegistrar: @unchecked Sendable {
    static let shared = FontRegistrar()

    private let lock = NSLock()
    private var registered = Set<FontResource>()

    func registerAll() {
        FontResource.all.forEach(register)
    }

    func register(_ resource: FontResource) {
        lock.lock()
        defer { lock.unlock() }

        guard !registered.contains(resource) else { return }

        guard let url = VultisigResources.bundle.url(
            forResource: resource.name,
            withExtension: resource.extension,
            subdirectory: "Fonts"
        ) else {
            return
        }

        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        registered.insert(resource)
    }
}
