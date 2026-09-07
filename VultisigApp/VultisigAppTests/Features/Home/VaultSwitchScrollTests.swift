import Combine
import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import VultisigApp

/// Hosts the production scroll views: value-only collapse tests cannot detect
/// a retained UIScrollView offset or a missing initial geometry callback.
@MainActor
final class VaultSwitchScrollTests: XCTestCase {
    private var token: TestContextToken?
    private var window: UIWindow?
    private weak var previousKeyWindow: UIWindow?
    private let collapse = HomeHeaderCollapse()

    override func setUpWithError() throws {
        let installed = try TestStore.installInMemoryContainer()
        token = installed
        // The DeFi screen starts unstructured refresh work across suspension.
        TestStore.retain(installed.container)
    }

    override func tearDownWithError() throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        previousKeyWindow?.makeKey()
        TestStore.restore(token)
        token = nil
    }

    func testWalletSwitchReturnsToTopAndExpandsBalance() async throws {
        let selection = VaultSelection(vault: makeVault("first"))
        try hostWallet(selection)
        let original = try await scrollDown(tab: .wallet)

        selection.vault = makeVault("second")
        try await settleLayout()

        let current = try verticalScrollView()
        XCTAssertFalse(current === original)
        assertAtTop(current, tab: .wallet)
    }

    func testWalletSwitchBetweenShortAndLongContentStaysAtTop() async throws {
        let long = makeVault("long")
        let short = TestStore.makeVault(pubKey: "short")
        let selection = VaultSelection(vault: long)
        try hostWallet(selection)
        try await settleLayout()

        for vault in [short, long, short] {
            selection.vault = vault
            try await settleLayout()
            assertAtTop(try verticalScrollView(), tab: .wallet)
        }
    }

    func testSameVaultRefreshPreservesScrollPosition() async throws {
        let selection = VaultSelection(vault: makeVault("refresh"))
        let model = LocalWalletModel()
        try hostWallet(selection, model: model)
        let original = try await scrollDown(tab: .wallet)
        let offset = original.contentOffset.y

        model.updateBalance(vault: selection.vault)
        try await settleLayout()

        let current = try verticalScrollView()
        XCTAssertTrue(current === original)
        XCTAssertEqual(current.contentOffset.y, offset, accuracy: 1)
        XCTAssertEqual(collapse.wallet.value, 1)
    }

    func testDefiSwitchReturnsToTopAndExpandsBalance() async throws {
        // Empty vaults avoid network balance work. The compact viewport makes
        // the real balance banner and customize-chains content scrollable.
        let selection = VaultSelection(vault: TestStore.makeVault(pubKey: "defi-first"))
        try host(DefiContent(selection: selection, collapse: collapse).frame(height: 300))
        let original = try await scrollDown(tab: .defi)

        selection.vault = TestStore.makeVault(pubKey: "defi-second")
        try await settleLayout()

        let current = try verticalScrollView()
        XCTAssertFalse(current === original)
        assertAtTop(current, tab: .defi)
    }

    func testInitialGeometryExpandsPreviouslyCollapsedHeader() async throws {
        collapse.update(tab: .wallet, offset: -200, restingOffset: 78)
        try host(
            VaultMainScreenScrollView(topInset: 78, onOffsetChange: { [collapse] offset in
                collapse.update(tab: .wallet, offset: offset, restingOffset: 78)
            }, content: {
                Color.clear.frame(height: 1_200)
            })
        )
        try await settleLayout()
        assertAtTop(try verticalScrollView(), tab: .wallet)
    }

    func testVaultSwitchClearsOpenWalletSearch() async throws {
        let selection = VaultSelection(vault: makeVault("search-first"))
        let model = LocalWalletModel()
        model.searchText = "bitcoin"
        try hostWallet(selection, model: model, startsInSearch: true)
        try await settleLayout()
        XCTAssertFalse(visibleTextFields(in: try XCTUnwrap(window)).isEmpty)

        selection.vault = makeVault("search-second")
        try await settleLayout()

        XCTAssertTrue(visibleTextFields(in: try XCTUnwrap(window)).isEmpty)
        XCTAssertEqual(model.searchText, "")
        assertAtTop(try verticalScrollView(), tab: .wallet)
    }

    func testVaultSwitchClearsOpenDefiSearch() async throws {
        let selection = VaultSelection(vault: TestStore.makeVault(pubKey: "defi-search-first"))
        let model = DefiMainViewModel()
        model.searchText = "bitcoin"
        try host(DefiSearchContent(selection: selection, collapse: collapse, model: model))
        try await settleLayout()
        XCTAssertFalse(visibleTextFields(in: try XCTUnwrap(window)).isEmpty)

        selection.vault = TestStore.makeVault(pubKey: "defi-search-second")
        try await settleLayout()

        XCTAssertTrue(visibleTextFields(in: try XCTUnwrap(window)).isEmpty)
        XCTAssertEqual(model.searchText, "")
        assertAtTop(try verticalScrollView(), tab: .defi)
    }

    func testRemovingSelectedDefiTabRestoresWallet() async throws {
        let tabs = TabSelection()
        tabs.selected = .defi
        try host(TabSelectionContent(model: tabs))
        try await settleLayout()
        XCTAssertEqual(tabs.selected, .defi)

        tabs.items = [.wallet]
        try await settleLayout()

        XCTAssertEqual(tabs.selected, .wallet)
    }

    func testTabbedVaultSwitchDoesNotTemporarilyCollapseBalances() async throws {
        let selection = VaultSelection(vault: TestStore.makeVault(pubKey: "tabs-first"))
        let tabs = TabSelection()
        var values: [Double] = []
        let wallet = collapse.$wallet.sink { values.append($0.value) }
        let defi = collapse.$defi.sink { values.append($0.value) }
        defer { wallet.cancel(); defi.cancel() }
        try host(TabbedVaultContent(selection: selection, tabs: tabs, collapse: collapse)
            .environmentObject(LocalWalletModel() as VaultDetailViewModel)
            .environmentObject(CoinSelectionViewModel()))
        try await settleLayout()
        tabs.selected = .defi
        try await settleLayout()
        selection.vault = TestStore.makeVault(pubKey: "tabs-second")
        try await settleLayout()
        XCTAssertEqual(tabs.selected, .defi)
        tabs.selected = .wallet
        try await settleLayout()
        tabs.selected = .defi
        try await settleLayout()

        XCTAssertTrue(values.allSatisfy { $0 == 0 }, "Unexpected collapse during tab layout: \(values)")
    }

    private func visibleTextFields(in view: UIView) -> [UITextField] {
        // Lazy containers may retain a removed field in an invisible subtree.
        guard !view.isHidden, view.alpha > 0 else { return [] }
        if let field = view as? UITextField { return [field] }
        return view.subviews.flatMap { visibleTextFields(in: $0) }
    }

    private func makeVault(_ name: String) -> Vault {
        let vault = TestStore.makeVault(pubKey: name)
        let chains: [Chain] = [
            .bitcoin, .ethereum, .solana, .thorChain, .litecoin,
            .dogecoin, .avalanche, .base, .arbitrum, .polygon
        ]
        vault.coins = chains.map { chain in
            let asset = CoinMeta(
                chain: chain, ticker: chain.ticker, logo: "", decimals: 8,
                priceProviderId: "", contractAddress: "", isNativeToken: true
            )
            return Coin(asset: asset, address: "fixture-\(name)-\(chain.name)", hexPublicKey: "")
        }
        return vault
    }

    private func hostWallet(
        _ selection: VaultSelection, model: LocalWalletModel? = nil, startsInSearch: Bool = false
    ) throws {
        try host(WalletContent(selection: selection, collapse: collapse, startsInSearch: startsInSearch)
            .environmentObject((model ?? LocalWalletModel()) as VaultDetailViewModel)
            .environmentObject(CoinSelectionViewModel()))
    }

    private func host(_ content: some View) throws {
        let token = try XCTUnwrap(token)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let controller = UIHostingController(rootView: NavigationStack {
            content
                .frame(width: 390, height: 600)
                .customNavigationBarHidden()
        }
        .modelContainer(token.container)
        .environmentObject(HomeViewModel())
        .environmentObject(SettingsViewModel.shared)
        .environmentObject(PushNotificationManager.shared)
        .environmentObject(AppViewModel.shared)
        .environmentObject(DeeplinkViewModel())
        .environmentObject(PhoneCheckUpdateViewModel())
        .environmentObject(SheetPresentedCounterManager()))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        self.window = window
        window.makeKeyAndVisible()
    }

    private func scrollDown(tab: HomeTab) async throws -> UIScrollView {
        try await settleLayout()
        let scroll = try verticalScrollView()
        let distance = HeaderCollapseProgress.distance(for: tab)
        let target = distance + 20
        let scrollableDistance = scroll.contentSize.height - scroll.bounds.height
            + scroll.adjustedContentInset.top + scroll.adjustedContentInset.bottom
        XCTAssertGreaterThan(scrollableDistance, target)
        scroll.setContentOffset(CGPoint(x: 0, y: target - scroll.adjustedContentInset.top), animated: false)
        try await settleLayout()
        XCTAssertGreaterThan(scroll.contentOffset.y + scroll.adjustedContentInset.top, distance)
        XCTAssertEqual(collapse.progress(for: tab).value, 1)
        return scroll
    }

    private func verticalScrollView() throws -> UIScrollView {
        let window = try XCTUnwrap(window)
        return try XCTUnwrap(scrollViews(in: window).first)
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        if let scroll = view as? UIScrollView { return [scroll] }
        return view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func assertAtTop(_ scroll: UIScrollView, tab: HomeTab, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(scroll.contentOffset.y + scroll.adjustedContentInset.top, 0, accuracy: 1, file: file, line: line)
        XCTAssertEqual(collapse.progress(for: tab).value, 0, file: file, line: line)
    }

    private func settleLayout() async throws {
        // Let SwiftUI's lazy layout and the carousel's entrance animation settle.
        try await Task.sleep(for: .milliseconds(600))
        window?.layoutIfNeeded()
    }
}

@MainActor
private final class VaultSelection: ObservableObject {
    @Published var vault: Vault
    init(vault: Vault) { self.vault = vault }
}

private struct WalletContent: View {
    @ObservedObject var selection: VaultSelection
    let collapse: HomeHeaderCollapse
    var startsInSearch = false

    var body: some View {
        VaultMainScreen(
            vault: selection.vault, routeToPresent: .constant(nil), addressToCopy: .constant(nil),
            showUpgradeVaultSheet: .constant(false), showBackupNow: .constant(false),
            collapse: collapse, shouldRefresh: .constant(false), onCamera: {},
            showSearchHeader: startsInSearch, focusSearch: startsInSearch
        )
    }
}

private struct DefiContent: View {
    @ObservedObject var selection: VaultSelection
    let collapse: HomeHeaderCollapse

    var body: some View {
        DefiMainScreen(vault: selection.vault, collapse: collapse)
    }
}

/// Keep actual rows and banners but replace remote refreshes with local projections.
@MainActor
private final class LocalWalletModel: VaultDetailViewModel {
    override func updateBalance(vault: Vault) { groupChains(vault: vault) }
    override func setupBanners(for _: Vault) { vaultBanners = [.followVultisig] }
    override func getGroupAsync(_: CoinSelectionViewModel) {}
}

@MainActor
private final class TabSelection: ObservableObject {
    @Published var selected: HomeTab = .wallet
    @Published var items: [HomeTab] = [.wallet, .defi]
}

private struct TabSelectionContent: View {
    @ObservedObject var model: TabSelection

    var body: some View {
        VultiTabBar(selectedItem: $model.selected, items: model.items, accessory: .camera) { tab in
            Text(tab.name)
        } onAccessory: {}
    }
}

private struct TabbedVaultContent: View {
    @ObservedObject var selection: VaultSelection
    @ObservedObject var tabs: TabSelection
    let collapse: HomeHeaderCollapse

    var body: some View {
        VultiTabBar(selectedItem: $tabs.selected, items: tabs.items, accessory: .camera) { tab in
            switch tab {
            case .wallet: WalletContent(selection: selection, collapse: collapse)
            case .defi: DefiContent(selection: selection, collapse: collapse)
            case .camera: EmptyView()
            }
        } onAccessory: {}
    }
}

private struct DefiSearchContent: View {
    @ObservedObject var selection: VaultSelection
    let collapse: HomeHeaderCollapse
    let model: DefiMainViewModel

    var body: some View {
        DefiMainScreen(
            vault: selection.vault, collapse: collapse,
            showSearchHeader: true, focusSearch: true, viewModel: model
        )
    }
}
