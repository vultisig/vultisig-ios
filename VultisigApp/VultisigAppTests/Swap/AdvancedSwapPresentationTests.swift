import SwiftUI
import UIKit
import XCTest

@testable import VultisigApp

/// These tests inspect the system presentation and the production scroll views,
/// so a content-dependent detent or an unscrollable child fails at runtime.
@MainActor
final class AdvancedSwapPresentationTests: XCTestCase {
    private var window: UIWindow?
    private weak var previousKeyWindow: UIWindow?

    override func tearDownWithError() throws {
        window?.endEditing(true)
        window?.rootViewController?.dismiss(animated: false)
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        previousKeyWindow?.makeKey()
    }

    func testEveryPageUsesTheSameSinglePresentationDetent() async throws {
        var initialFrame: CGRect?
        for state in AdvancedSwapSheetType.allCases {
            let host = try hostSheet(state: state)
            try await settle()
            let controller = try XCTUnwrap(host.presentedViewController)
            let frame = controller.view.convert(controller.view.bounds, to: window)
            XCTAssertEqual(controller.sheetPresentationController?.detents.count, 1, "\(state)")
            if let initialFrame {
                XCTAssertEqual(frame.minY, initialFrame.minY, accuracy: 1, "\(state)")
                XCTAssertEqual(frame.height, initialFrame.height, accuracy: 1, "\(state)")
            } else {
                initialFrame = frame
            }
        }
    }

    func testQuoteRefreshChangesRenderedRowsWithoutMovingTheOpenSheet() async throws {
        let model = SwapDetailsViewModel()
        let host = try hostSheet(model: model)
        try await settle()
        let controller = try XCTUnwrap(host.presentedViewController)
        let original = controller.view.convert(controller.view.bounds, to: window)
        let originalContentHeight = try scrollView(in: controller.view).contentSize.height

        for quotes in [sampleQuotes(), [], sampleQuotes(), []] {
            model.allQuotes = quotes
            try await settle()
            let current = controller.view.convert(controller.view.bounds, to: window)
            XCTAssertEqual(current.minY, original.minY, accuracy: 1)
            XCTAssertEqual(current.height, original.height, accuracy: 1)
            XCTAssertEqual(controller.sheetPresentationController?.detents.count, 1)
            let contentHeight = try scrollView(in: controller.view).contentSize.height
            if quotes.isEmpty {
                XCTAssertEqual(contentHeight, originalContentHeight, accuracy: 1)
            } else {
                XCTAssertGreaterThan(contentHeight, originalContentHeight + 50)
            }
        }
    }

    func testMainContentHeightMatchesAllSixSupportedRowCombinations() async throws {
        let combinations = [
            (gas: false, provider: false, secured: false),
            (gas: false, provider: true, secured: false),
            (gas: true, provider: false, secured: false),
            (gas: true, provider: true, secured: false),
            (gas: false, provider: false, secured: true),
            (gas: false, provider: true, secured: true)
        ]
        for combination in combinations {
            let model = SwapDetailsViewModel()
            model.fromCoin = coin(chain: .bitcoin, secured: false)
            model.toCoin = coin(chain: combination.secured ? .thorChain : .bitcoin, secured: combination.secured)
            model.allQuotes = combination.provider ? sampleQuotes() : []
            XCTAssertEqual(model.isSecuredMint, combination.secured)
            let host = try hostSheet(model: model, gasSupported: combination.gas)
            try await settle()
            let controller = try XCTUnwrap(host.presentedViewController)
            let scroll = try scrollView(in: controller.view)
            var rows: [(ImageResource, String, String)] = [(.bolt, "slippageTolerance", "auto")]
            if combination.gas { rows.append((.gasPump, "gasLimit", "auto")) }
            if combination.provider { rows.append((.branchOut, "selectRoute", "auto")) }
            if !combination.secured { rows.append((.clone2, "useExternalRecipient", "off")) }
            let rowHeight = rows.reduce(CGFloat.zero) { total, row in
                let view = AdvancedSwapMainRow(icon: row.0, title: row.1.localized, value: row.2.localized) {}
                let measured = UIHostingController(rootView: view)
                return total + measured.sizeThatFits(in: CGSize(width: scroll.bounds.width - 32, height: 1_000)).height
            }
            let expected = rowHeight + CGFloat(rows.count - 1) + AdvancedSwapSheet.MainLayout.cardInset
            XCTAssertEqual(scroll.contentSize.height, expected, accuracy: 2, "\(combination)")
        }
    }

    func testSlippageCustomFieldCanScrollIntoCompactViewport() async throws {
        let host = try hostContent(SlippageSettingsView(slippage: .constant(.custom(bps: 100))) {})
        try await settle()
        try assertScrollableContent(in: host.view)
        try assertLastFieldReachable(in: host.view)
    }

    func testGasFieldCanScrollIntoCompactViewport() async throws {
        let host = try hostContent(GasLimitSettingsView(gasLimit: .constant(nil)) {})
        try await settle()
        try assertScrollableContent(in: host.view)
        try assertLastFieldReachable(in: host.view)
    }

    func testRecipientFieldCanScrollIntoCompactViewport() async throws {
        let host = try hostContent(ExternalRecipientSettingsView(coin: .example, recipient: .constant(nil)) {})
        try await settle()
        try assertScrollableContent(in: host.view)
        try assertLastFieldReachable(in: host.view)
    }

    func testRouteListUsesOneEnabledScrollViewWhenContentOverflows() async throws {
        let model = SwapDetailsViewModel()
        model.allQuotes = sampleQuotes()
        let host = try hostContent(SelectRouteSettingsView(detailsViewModel: model) {})
        try await settle()
        let scrolls = descendants(in: host.view).compactMap { $0 as? UIScrollView }
        XCTAssertEqual(scrolls.count, 1)
        try assertScrollableContent(in: host.view)
    }

    func testFocusedFieldsCanBeScrolledIntoVisibleViewport() async throws {
        for state in [AdvancedSwapSheetType.slippage, .gasLimit, .externalRecipient] {
            let host = try hostSheet(state: state)
            try await settle()
            let controller = try XCTUnwrap(host.presentedViewController)
            let field = try XCTUnwrap(descendants(in: controller.view).compactMap { $0 as? UITextField }.last)
            defer { field.resignFirstResponder() }
            XCTAssertTrue(field.becomeFirstResponder(), "\(state)")
            try await settle()
            XCTAssertTrue(field.isFirstResponder, "\(state)")
            try assertLastFieldReachable(in: controller.view)
        }
    }

    private func assertLastFieldReachable(in view: UIView) throws {
        let scroll = try scrollView(in: view)
        let field = try XCTUnwrap(descendants(in: scroll).compactMap { $0 as? UITextField }.last)
        let fieldFrame = field.convert(field.bounds, to: scroll)
        scroll.scrollRectToVisible(fieldFrame.insetBy(dx: 0, dy: -8), animated: false)
        view.layoutIfNeeded()
        let visible = scroll.bounds.inset(by: scroll.adjustedContentInset)
        XCTAssertTrue(scroll.isScrollEnabled)
        XCTAssertTrue(scroll.panGestureRecognizer.isEnabled)
        // Address inputs intentionally scroll horizontally. Their entire
        // height, and a tappable portion of their width, must remain visible.
        let currentField = field.convert(field.bounds, to: scroll)
        XCTAssertGreaterThanOrEqual(currentField.minY, visible.minY - 0.5)
        XCTAssertLessThanOrEqual(currentField.maxY, visible.maxY + 0.5)
        XCTAssertGreaterThan(visible.intersection(currentField).width, 0)
        XCTAssertGreaterThan(visible.height, 0)
    }

    private func assertScrollableContent(in view: UIView) throws {
        let scroll = try scrollView(in: view)
        let visible = scroll.bounds.inset(by: scroll.adjustedContentInset)
        XCTAssertTrue(scroll.isScrollEnabled)
        XCTAssertTrue(scroll.panGestureRecognizer.isEnabled)
        XCTAssertGreaterThan(visible.height, 0)
        XCTAssertGreaterThan(scroll.contentSize.height, visible.height)
    }

    private func hostSheet(
        state: AdvancedSwapSheetType = .main,
        model: SwapDetailsViewModel? = nil,
        gasSupported: Bool = true
    ) throws -> UIViewController {
        try host(PresentationHost(state: state, model: model ?? SwapDetailsViewModel(), gasSupported: gasSupported))
    }

    private func hostContent(_ content: some View) throws -> UIViewController {
        try host(content.environment(\.dynamicTypeSize, .accessibility5).frame(width: 375, height: 180))
    }

    private func host(_ content: some View) throws -> UIViewController {
        window?.endEditing(true)
        window?.rootViewController?.dismiss(animated: false)
        window?.isHidden = true
        window?.rootViewController = nil
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        if previousKeyWindow == nil { previousKeyWindow = scene.windows.first(where: \.isKeyWindow) }
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: content)
        window.rootViewController = host
        self.window = window
        window.makeKeyAndVisible()
        return host
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(900))
        window?.layoutIfNeeded()
    }

    private func scrollView(in view: UIView) throws -> UIScrollView {
        try XCTUnwrap(descendants(in: view).compactMap { $0 as? UIScrollView }.first)
    }

    private func descendants(in view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants(in: $0) }
    }

    private func sampleQuotes() -> [SwapQuote] {
        let quote = EVMQuote(dstAmount: "100", tx: EVMQuote.Transaction(
            from: "0xf", to: "0xt", data: "0x", value: "0", gasPrice: "0", gas: 0
        ))
        return [.oneinch(quote, fee: nil), .kyberswap(quote, fee: nil), .lifi(quote, fee: nil, integratorFee: nil)]
    }

    private func coin(chain: Chain, secured: Bool) -> Coin {
        let asset = CoinMeta(chain: chain, ticker: "BTC", logo: "", decimals: 8, priceProviderId: "",
                             contractAddress: secured ? "btc-btc" : "", isNativeToken: !secured)
        return Coin(asset: asset, address: "test-address", hexPublicKey: "test-public-key")
    }
}

private struct PresentationHost: View {
    let state: AdvancedSwapSheetType
    let model: SwapDetailsViewModel
    let gasSupported: Bool
    @State private var presented = false
    @State private var settings = SwapAdvancedSettings.default

    var body: some View {
        Color.clear
            .sheet(isPresented: $presented) {
                AdvancedSwapSheet(isPresented: $presented, coin: .example, isGasLimitSupported: gasSupported,
                                  settings: $settings, detailsViewModel: model, sheetType: state)
            }
            .onAppear { presented = true }
    }
}
