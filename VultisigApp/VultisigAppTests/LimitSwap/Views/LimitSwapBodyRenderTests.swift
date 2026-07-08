//
//  LimitSwapBodyRenderTests.swift
//  VultisigAppTests
//
//  Figma-parity render harness for the THORChain limit-swap accordion. NOT an
//  assertion test — it renders `LimitSwapBodyView` in isolation (populated
//  Figma state) for both accordion states and writes the frames to disk so the
//  polish pass can be eyeballed against Figma `78798:74520`.
//
//  Runs only when `LIMIT_RENDER_OUT` names an output directory, so the regular
//  unit-test suite skips it.
//

#if os(iOS)
@testable import VultisigApp
import BigInt
import SwiftUI
import UIKit
import XCTest

@MainActor
final class LimitSwapBodyRenderTests: XCTestCase {

    private var storeToken: TestContextToken!
    private var vault: Vault!
    private var fromCoin: Coin!
    private var toCoin: Coin!

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault()

        // Figma pair: Sell USDT → Buy BTC.
        fromCoin = Coin(
            asset: CoinMeta.make(chain: .ethereum, ticker: "USDT", decimals: 6, isNativeToken: false),
            address: "0xusdtsourceaddress000000000000000000000000",
            hexPublicKey: "usdt-pubkey"
        )
        fromCoin.rawBalance = "1000000000" // 1,000 USDT
        toCoin = Coin(
            asset: CoinMeta.make(chain: .bitcoin, ticker: "BTC", decimals: 8),
            address: "bc1qbtcdestaddress0000000000000000000000000",
            hexPublicKey: "btc-pubkey"
        )
        toCoin.rawBalance = "5000000" // 0.05 BTC
        vault.coins.append(fromCoin)
        vault.coins.append(toCoin)
    }

    override func tearDown() async throws {
        fromCoin = nil
        toCoin = nil
        vault = nil
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    func testRenderExecuteWhenExpanded() throws {
        try render(initialFocus: .executeWhen, fileName: "executewhen")
    }

    func testRenderAssetExpanded() throws {
        try render(initialFocus: .asset, fileName: "asset")
    }

    // MARK: - Harness

    private func render(
        initialFocus: LimitSwapBodyView.FocusedSection,
        fileName: String
    ) throws {
        // Runtime env vars can't be injected into app-hosted unit tests from the
        // xcodebuild command line (the `TEST_RUNNER_` prefix isn't forwarded), so
        // the harness reads its output directory from a sentinel file the runner
        // drops in the simulator's host home. Absent that file the test skips, so
        // the normal `make test` suite never renders.
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMULATOR_HOST_HOME"] else {
            throw XCTSkip("Render harness runs only on the iOS simulator (needs SIMULATOR_HOST_HOME).")
        }
        let sentinel = home + "/.vultisig-limit-render-out"
        guard let raw = try? String(contentsOfFile: sentinel, encoding: .utf8),
              case let outDir = raw.trimmingCharacters(in: .whitespacesAndNewlines),
              !outDir.isEmpty else {
            throw XCTSkip("Write an output directory to \(sentinel) to run the render harness.")
        }

        let view = LimitSwapBodyView(
            vm: makeViewModel(),
            fromCoin: fromCoin,
            toCoin: toCoin,
            initialFocusedSection: initialFocus,
            onPickFromAsset: {},
            onPickToAsset: {},
            onSwapAssets: {},
            onPlaceOrder: {}
        )
        .frame(width: 393)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.colors.bgPrimary)
        .environment(\.colorScheme, .dark)

        let url = URL(fileURLWithPath: outDir)
            .appendingPathComponent("\(fileName).png")
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: outDir),
            withIntermediateDirectories: true
        )
        renderHosted(view, size: CGSize(width: 393, height: 852), to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "PNG not written to \(url.path)")
    }

    private func makeViewModel() -> LimitSwapFormViewModel {
        let quoteService = MockLimitSwapQuoteService()
        let interactor = DefaultLimitSwapInteractor(quoteService: quoteService)
        let draft = LimitSwapDraft(
            fromAsset: LimitSwapAsset(coin: fromCoin),
            toAsset: LimitSwapAsset(coin: toCoin),
            sourceAmount: BigInt("1000000000"), // 1,000 USDT
            targetPrice: Decimal(string: "65800.13")!,
            displayUnit: .usd
        )
        let vm = LimitSwapFormViewModel(initialDraft: draft, vault: vault, interactor: interactor)
        vm.marketPriceRef = Decimal(string: "67240")!
        vm.targetUsdPricePerUnit = 1
        vm.advancedSwapQueueEnabled = true
        vm.quoteRefreshCountdown = 36 // matches Figma "0:36"
        return vm
    }

    /// Hosts the SwiftUI view in a real window so its lifecycle runs
    /// (`.onLoad`/`.onChange` fire and the section expand animation settles) —
    /// `ImageRenderer` renders a static graph without lifecycle, so the
    /// accordion would stay collapsed. Captures at @3x.
    private func renderHosted<V: View>(_ view: V, size: CGSize, to url: URL) {
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = UIColor(Theme.colors.bgPrimary)

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // Let onAppear/onLoad + the expand animation + one countdown tick settle.
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        try? image.pngData()?.write(to: url)
    }
}
#endif
