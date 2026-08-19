//
//  TransactionHeroResolverTests.swift
//  VultisigAppTests
//
//  Pins provider precedence, surface entitlements, and screen hookups.
//

@testable import VultisigApp
import XCTest

final class TransactionHeroResolverTests: XCTestCase {

    func testFractionalWithdrawalUsesProjectedSemantics() {
        let coin = Coin(asset: TokensStore.tcy, address: "thor1local", hexPublicKey: "00")
        let transaction = TCYUnstakeTransactionBuilder(
            coin: coin,
            basisPoints: 5_006,
            autoCompoundAmount: 0,
            sendMaxAmount: false,
            isAutoCompound: false,
            stakedAmount: Decimal(string: "2002.74")!
        ).buildSendTransaction(vault: .example)

        let hero = TransactionHeroResolver.hero(
            on: .functionCallVerify,
            for: .initiating(transaction)
        )
        guard case .projected(_, let estimate, let scope) = hero else {
            return XCTFail("fractional withdrawal must not look like a committed send amount")
        }
        XCTAssertTrue(estimate?.amount.hasPrefix("1,002.571644") ?? false)
        XCTAssertTrue(scope.contains("50.06"), "the committed fraction should remain visible: \(scope)")
    }

    // MARK: - The order

    func testProvidersAreAskedInTheDeclaredOrder() {
        XCTAssertEqual(
            TransactionHeroResolver.providers.map(\.id),
            [.rippleTrustSet, .quotedWithdrawal, .limitOrderCancel, .limitOrderPlacement, .simulated, .decoded],
            """
            The order is the answer to two providers claiming one transaction, \
            and it has to stay the one the four `??` chains gave, plus \
            quotedWithdrawal reinstating the fractional-withdrawal hero ahead of \
            the decoded reading. Changing it changes what a signing screen says.
            """
        )
    }

    /// Exercises resolution behavior rather than only inspecting the array.
    func testTheOrderDecidesWhenTwoProvidersBothClaim() {
        let earlier = HeroContent.title(text: "earlier", caption: nil)
        let later = HeroContent.title(text: "later", caption: nil)

        let claimants: [TransactionHeroProvider] = [
            TransactionHeroProvider(id: .rippleTrustSet, surfaces: [.sendDone], hero: { _ in earlier }),
            TransactionHeroProvider(id: .limitOrderCancel, surfaces: [.sendDone], hero: { _ in later })
        ]

        let resolved = TransactionHeroResolver.hero(
            on: .sendDone,
            for: .cosigning(payload: nil, simulated: { nil }),
            providers: claimants
        )
        XCTAssertEqual(resolved, earlier, "the first claimant in order must win")
    }

    /// A provider not entitled to the surface is skipped even when it would claim.
    func testAProviderIsNotAskedOnASurfaceItIsNotEntitledTo() {
        let claimed = HeroContent.title(text: "claimed", caption: nil)
        let notEntitled = [
            TransactionHeroProvider(id: .simulated, surfaces: [.keysignDone], hero: { _ in claimed })
        ]

        XCTAssertNil(
            TransactionHeroResolver.hero(
                on: .sendDone,
                for: .cosigning(payload: nil, simulated: { nil }),
                providers: notEntitled
            ),
            "entitlement is what encodes the per-screen asymmetries; ignoring it collapses them"
        )
    }

    /// Earlier providers must win without evaluating lazy simulation state.
    func testTheSimulationIsNotEvaluatedWhenAnEarlierProviderClaims() {
        var evaluated = false
        let claimants: [TransactionHeroProvider] = [
            TransactionHeroProvider(
                id: .limitOrderCancel,
                surfaces: [.keysignConfirm],
                hero: { _ in .title(text: "cancel", caption: nil) }
            ),
            .simulated
        ]

        _ = TransactionHeroResolver.hero(
            on: .keysignConfirm,
            for: .cosigning(payload: nil, simulated: {
                evaluated = true
                return .title(text: "simulated", caption: nil)
            }),
            providers: claimants
        )

        XCTAssertFalse(evaluated, "the simulation was built even though a cancel had already claimed the hero")
    }

    func testEveryProviderIsRegisteredExactlyOnce() {
        let ids = TransactionHeroResolver.providers.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "a provider is registered twice")
    }

    /// Surface entitlements preserve the previous, intentionally asymmetric chains.
    func testEachSurfaceAsksExactlyTheProvidersItsOldChainAsked() {
        let expected: [TransactionHeroSurface: [TransactionHeroProvider.ID]] = [
            // Exact initiator payout precedes the decoded fraction.
            .functionCallVerify: [.quotedWithdrawal, .limitOrderCancel, .decoded],
            .sendVerify: [.decoded],
            .sendDone: [.rippleTrustSet, .limitOrderCancel],
            .keysignConfirm: [.limitOrderCancel, .limitOrderPlacement, .simulated, .decoded],
            .keysignDone: [.rippleTrustSet, .limitOrderCancel, .simulated]
        ]

        for surface in TransactionHeroSurface.allCases {
            let asked = TransactionHeroResolver.providers
                .filter { $0.surfaces.contains(surface) }
                .map(\.id)
            XCTAssertEqual(asked, expected[surface], "\(surface) no longer asks what its old chain asked")
        }
    }

    @MainActor
    func testResolvedProjectionIsVerifyOnlyAndCannotChangeDoneHeroContent() {
        let viewModel = JoinKeysignViewModel()
        let projection = HeroContent.projected(
            title: "You’re delegating",
            estimate: HeroCoinAmount(amount: "2", ticker: "SOL", logo: "solana"),
            scope: "scope"
        )

        viewModel.resolvedHero = projection

        XCTAssertNil(viewModel.heroContent, "Done must keep its pre-decoder provider path")
        XCTAssertEqual(viewModel.verifyHeroContent, projection)
    }

    @MainActor
    func testExactHeroCanAcquireFiatWhenARateArrivesAfterItsFirstFrame() throws {
        let providerId = "decoder-hero-\(UUID().uuidString)"
        let coin = Coin(
            asset: CoinMeta(
                chain: .solana,
                ticker: "SOL",
                logo: "solana",
                decimals: 9,
                priceProviderId: providerId,
                contractAddress: "",
                isNativeToken: true
            ),
            address: "owner",
            hexPublicKey: "hex"
        )
        let decoded = DecodedTransaction(
            operation: .stake,
            amount: .units(2_000_000_000, of: .transactionCoin),
            evidence: .structuredPayload
        )
        let initial = try XCTUnwrap(DecodedTransactionPresentation.hero(for: decoded, coin: coin))
        guard case .send(_, let unpriced) = initial else { return XCTFail("expected an exact amount") }
        XCTAssertNil(unpriced.fiat)

        try RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: providerId, value: 100)
        ])

        guard case .send(_, let repriced) = initial.refreshedFiat() else {
            return XCTFail("refreshing fiat changed the hero shape")
        }
        XCTAssertNotNil(repriced.fiat)
        XCTAssertFalse(repriced.fiat?.isEmpty ?? true)
    }

    // MARK: - Source-level hookup checks

    private func appSource(_ relativePath: String, file: StaticString = #filePath) throws -> String {
        let testsRoot = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appRoot = testsRoot.deletingLastPathComponent().appendingPathComponent("VultisigApp")
        return try String(contentsOf: appRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testEveryVerifySurfaceIsWiredToTheResolverBySomeScreen() throws {
        let hookups: [(path: String, surface: String)] = [
            ("Features/FunctionTransaction/Common/Screen/FunctionTransactionVerifyScreen.swift", ".functionCallVerify"),
            ("Features/Send/Views/Screens/SendVerifyScreen.swift", ".sendVerify"),
            ("Features/Keysign/Views/KeysignMessageConfirmView.swift", ".keysignConfirm")
        ]

        for hookup in hookups {
            let source = try appSource(hookup.path)
            XCTAssertTrue(
                source.contains("TransactionHeroResolver.hero(") && source.contains("on: \(hookup.surface)"),
                """
                \(hookup.path) no longer asks the resolver for \(hookup.surface). \
                If the screen genuinely should not, remove its surface from the \
                registry too — a surface nothing asks for is a rank nobody applies.
                """
            )
        }
    }

    func testCosmosStakingSummaryUsesTheSharedHeroVocabulary() throws {
        let source = try appSource(
            "Features/FunctionTransaction/Common/View/CosmosStakingVerifySummaryView.swift"
        )
        XCTAssertTrue(source.contains("TransactionHeroResolver.hero("))
        XCTAssertTrue(source.contains("HeroContentView(content: hero)"))
        XCTAssertFalse(source.contains("private var headlineKey"))
    }

    /// The presentations the registry owns are reached through it, not around it.
    func testNoScreenCallsAProviderPresentationDirectly() throws {
        let screens = [
            "Features/FunctionTransaction/Common/Screen/FunctionTransactionVerifyScreen.swift",
            "Features/Send/Views/Screens/SendVerifyScreen.swift",
            "Features/Keysign/Views/KeysignMessageConfirmView.swift"
        ]

        for screen in screens {
            let source = try appSource(screen)
            let ownedByTheRegistry = [
                "RippleTrustSetPresentation.hero(",
                "LimitOrderCancelPresentation.hero(",
                "LimitOrderPlacementPresentation.hero(",
                "DecodedTransactionPresentation.hero("
            ]
            for presentation in ownedByTheRegistry {
                XCTAssertFalse(
                    source.contains(presentation),
                    "\(screen) calls \(presentation) directly, bypassing the one precedence order"
                )
            }
        }
    }
}
