//
//  ShareSheetViewModelTests.swift
//  VultisigApp
//
//  Pins `ShareSheetViewModel` as the single source of truth for the join-URL
//  string shared between the QR image, the copy-link action, and today's
//  system share caption. `render()` must store `qrCodeData` byte-identical to
//  whatever the caller passed in, regardless of the URL's shape (relay
//  jsonData, local-mode jsonData, or a short payload-id form) — a "Copy Link"
//  action that reads this property can never diverge from what the QR
//  encodes. `qrCodeImage` must likewise carry the exact plain QR image passed
//  into `render()`, so a preview built from it never re-derives the QR.
//

@testable import VultisigApp
import SwiftUI
import XCTest

final class ShareSheetViewModelTests: XCTestCase {

    @MainActor
    func testRenderStoresRelayJsonDataURLUnchanged() {
        assertRenderStoresQrCodeDataUnchanged(
            "https://vultisig.com?type=SignTransaction&vault=03abc123&jsonData=%7B%22sessionID%22%3A%22s1%22%2C%22useVultisigRelay%22%3Atrue%7D"
        )
    }

    @MainActor
    func testRenderStoresLocalModeURLUnchanged() {
        assertRenderStoresQrCodeDataUnchanged(
            "https://vultisig.com?type=SignTransaction&vault=03abc123&jsonData=%7B%22sessionID%22%3A%22s1%22%2C%22useVultisigRelay%22%3Afalse%7D"
        )
    }

    @MainActor
    func testRenderStoresShortPayloadIdURLUnchanged() {
        assertRenderStoresQrCodeDataUnchanged(
            "https://vultisig.com?type=SignTransaction&vault=03abc123&jsonData=%7B%22payloadID%22%3A%22deadbeef%22%7D"
        )
    }

    @MainActor
    private func assertRenderStoresQrCodeDataUnchanged(
        _ qrCodeData: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let viewModel = ShareSheetViewModel()
        let qrImage = Image(systemName: "qrcode")

        viewModel.render(
            qrCodeImage: qrImage,
            qrCodeData: qrCodeData,
            displayScale: 2,
            type: .Send
        )

        XCTAssertEqual(
            viewModel.qrCodeData,
            qrCodeData,
            "Copy Link must read back the exact string handed to render(), never a reconstructed URL",
            file: file,
            line: line
        )
        XCTAssertNotNil(viewModel.qrCodeImage, "qrCodeImage must be populated by render()", file: file, line: line)
        XCTAssertNotNil(viewModel.renderedImage, "renderedImage (branded card) must still be populated", file: file, line: line)
    }

    @MainActor
    func testClearResetsQrCodeImageAlongsideOtherState() {
        let viewModel = ShareSheetViewModel()
        viewModel.render(qrCodeImage: Image(systemName: "qrcode"), qrCodeData: "https://vultisig.com?x=1", displayScale: 2, type: .Send)

        viewModel.clear()

        XCTAssertNil(viewModel.qrCodeImage)
        XCTAssertNil(viewModel.qrCodeData)
        XCTAssertNil(viewModel.renderedImage)
    }
}
