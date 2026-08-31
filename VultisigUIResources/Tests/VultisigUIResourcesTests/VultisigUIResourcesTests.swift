import XCTest
@testable import VultisigUIResources

#if canImport(AppKit)
import AppKit
#endif

final class VultisigUIResourcesTests: XCTestCase {
    func testFontFilesAreBundled() {
        for resource in FontResource.all {
            XCTAssertNotNil(
                VultisigResources.bundle.url(
                    forResource: resource.name,
                    withExtension: resource.extension,
                    subdirectory: "Fonts"
                ),
                "Missing bundled font: \(resource.name).\(resource.extension)"
            )
        }
    }

    func testFontsRegisterWithTheirPostScriptNames() {
        VultisigResources.registerFonts()

        #if canImport(AppKit)
        for font in VultisigFont.allCases {
            XCTAssertNotNil(
                NSFont(name: font.postScriptName, size: 16),
                "Unable to register font: \(font.postScriptName)"
            )
        }
        #endif
    }

    func testImagesAreBundled() {
        let sourceCatalog = VultisigResources.bundle.url(
            forResource: "Images",
            withExtension: "xcassets"
        )
        let compiledCatalog = VultisigResources.bundle.url(
            forResource: "Assets",
            withExtension: "car"
        )

        XCTAssertTrue(sourceCatalog != nil || compiledCatalog != nil)
        XCTAssertEqual(VultisigImage.allCases.count, 6)
    }
}
