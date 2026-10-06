import Foundation
import XCTest
@testable import VultisigApp

@MainActor
final class TransactionActivityPolicyTests: XCTestCase {
    func testRouteLabelsUseDurableReceiptFieldsAndRespectPrivacy() {
        for type in [TransactionHistoryType.send, .swap, .limit, .approve, .transaction] {
            let row = ActivityTestFixture.row(type: type, amountCrypto: "1.234 ETH", toCoinTicker: "BTC")
            let state = TransactionActivityPolicy.state(for: row, phase: .pending, observedAt: row.createdAt,
                revision: 1, delayed: false, showDetails: true)
            XCTAssertEqual(state.sourceSummary, "1.234 ETH")
            XCTAssertEqual(state.destinationTicker, type == .swap || type == .limit ? "BTC" : nil)
            XCTAssertEqual(state.recipient, type == .send ? "0x12…7890" : nil)
            let hidden = TransactionActivityPolicy.state(for: row, phase: .pending, observedAt: row.createdAt,
                revision: 2, delayed: false, showDetails: false)
            XCTAssertNil(hidden.sourceSummary)
            XCTAssertNil(hidden.destinationTicker)
            XCTAssertFalse(hidden.hasDetails)
        }
        let unknownAmount = ActivityTestFixture.row(type: .transaction, amountCrypto: "")
        let state = TransactionActivityPolicy.state(for: unknownAmount, phase: .pending, observedAt: unknownAmount.createdAt,
            revision: 1, delayed: false, showDetails: true)
        XCTAssertEqual(state.sourceSummary, "ETH")
    }

    func testAvailabilityIsPlatformBasedRatherThanBuildConfiguration() {
        #if os(iOS)
        XCTAssertTrue(TransactionActivityPolicy.isSupportedPlatform)
        #else
        XCTAssertFalse(TransactionActivityPolicy.isSupportedPlatform)
        #endif
    }

    func testSwapSourceConfirmationNeverSettlesSwap() {
        let row = ActivityTestFixture.row(type: .swap, status: .successful)
        XCTAssertEqual(TransactionActivityPolicy.phase(for: row), .sourceConfirmed)
        XCTAssertFalse(TransactionActivityPolicy.phase(for: row).isTerminal)
    }

    func testProviderOutcomeMatrixSeparatesSettlementFromOperationalErrors() {
        let outcomes: [String: TransactionActivityState.Phase] = [
            "completed": .completed, "refunded": .refunded, "partially_refunded": .partiallyRefunded,
            "reverted": .failed, "failed": .failed, "outbound": .swapping, "swapping": .swapping,
            "not_started": .pending, "starting": .pending, "broadcasted": .pending, "mempool": .pending,
            "inbound": .pending, "dropped": .pending, "replaced": .pending,
            "retries_exceeded": .pending, "parsing_error": .pending, "unknown": .pending, "future_status": .pending
        ]
        for (raw, expected) in outcomes {
            let row = ActivityTestFixture.row(type: .swap, tracking: .init(providerKind: "swapKit", latestTrackingStatus: raw))
            XCTAssertEqual(TransactionActivityPolicy.phase(for: row), expected, raw)
            let operational = ["dropped", "replaced", "retries_exceeded", "parsing_error", "unknown", "future_status"].contains(raw)
            XCTAssertEqual(TransactionActivityPolicy.providerIsDelayed(row), operational, raw)
        }
    }

    func testCoarseOnlyProviderSettlementAndFineStatusPrecedence() {
        for (raw, expected) in [("completed", TransactionActivityState.Phase.completed), ("refunded", .refunded), ("failed", .failed)] {
            let row = ActivityTestFixture.row(type: .swap, tracking: .init(providerKind: "swapKit", latestStatus: raw))
            XCTAssertEqual(TransactionActivityPolicy.phase(for: row), expected)
        }
        let row = ActivityTestFixture.row(type: .swap, tracking: .init(providerKind: "swapKit",
                                                                       latestStatus: "completed", latestTrackingStatus: "inbound"))
        XCTAssertEqual(TransactionActivityPolicy.phase(for: row), .pending)
    }

    func testDurableNativeSwapFailureDoesNotConflateProviderOutageOrTimeout() {
        XCTAssertEqual(TransactionActivityPolicy.phase(for: ActivityTestFixture.row(type: .swap, status: .error)), .failed)
        let timeout = ActivityTestFixture.row(type: .swap, status: .error, error: "timeout".localized)
        XCTAssertEqual(TransactionActivityPolicy.phase(for: timeout), .pending)
        let providerError = ActivityTestFixture.row(type: .swap, status: .error,
                                                    tracking: .init(providerKind: "swapKit", latestTrackingStatus: "parsing_error"))
        XCTAssertEqual(TransactionActivityPolicy.phase(for: providerError), .pending)
    }

    func testAssetMappingUsesDurableLogoIdentityAndPrivacyGate() {
        let row = ActivityTestFixture.row(type: .swap, coinLogo: "usdc", toCoinLogo: "eth")
        let rich = TransactionActivityPolicy.state(for: row, phase: .pending, observedAt: row.createdAt,
                                                   revision: 1, delayed: false, showDetails: true)
        XCTAssertEqual(rich.sourceAssetID, "usdc")
        XCTAssertEqual(rich.destinationAssetID, "eth")
        let hidden = TransactionActivityPolicy.state(for: row, phase: .pending, observedAt: row.createdAt,
                                                     revision: 2, delayed: false, showDetails: false)
        XCTAssertNil(hidden.sourceAssetID)
        XCTAssertNil(hidden.destinationAssetID)
        let remote = ActivityTestFixture.row(type: .swap, coinLogo: "https://example.com/eth.svg", toCoinLogo: "unknown")
        let fallback = TransactionActivityPolicy.state(for: remote, phase: .pending, observedAt: row.createdAt,
                                                       revision: 1, delayed: false, showDetails: true)
        // Its ticker says ETH/BTC, but neither establishes the bundled logo identity.
        XCTAssertNil(fallback.sourceAssetID)
        XCTAssertNil(fallback.destinationAssetID)
    }

    func testRUNEAndLimitDestinationUseActualResourceIdentity() {
        let row = ActivityTestFixture.row(type: .limit, coinLogo: "rune", toCoinLogo: "chain-rune")
        let state = TransactionActivityPolicy.state(for: row, phase: .pending, observedAt: row.createdAt,
            revision: 1, delayed: false, showDetails: true)
        XCTAssertEqual(state.sourceAssetID, "rune")
        XCTAssertEqual(state.destinationAssetID, "chain-rune")
    }

    func testPreparedKeysAreInjectedAndPrivateModeNeverReadsCache() {
        let source = "https://example.com/source.png"
        let destination = "https://example.com/destination.png"
        let sourceKey = String(repeating: "a", count: 64)
        let destinationKey = String(repeating: "b", count: 64)
        for type in [TransactionHistoryType.swap, .limit] {
            let row = ActivityTestFixture.row(type: type, coinLogo: source, toCoinLogo: destination)
            let state = TransactionActivityPolicy.state(for: row, phase: .pending, observedAt: row.createdAt,
                revision: 1, delayed: false, showDetails: true,
                preparedImageKey: { $0 == source ? sourceKey : destinationKey })
            XCTAssertNil(state.sourceAssetID)
            XCTAssertNil(state.destinationAssetID)
            XCTAssertEqual(state.sourceImageKey, sourceKey)
            XCTAssertEqual(state.destinationImageKey, destinationKey)
            XCTAssertEqual(TransactionActivityPolicy.remoteImageURLs(for: row).map(\.absoluteString), [source, destination])
            let hidden = TransactionActivityPolicy.state(for: row, phase: .pending, observedAt: row.createdAt,
                revision: 1, delayed: false, showDetails: false,
                preparedImageKey: { _ in XCTFail("Private state must not inspect images"); return sourceKey })
            XCTAssertFalse(hidden.hasDetails)
        }
    }

    func testLimitOrderConfirmationCannotMasqueradeAsAFill() {
        for (status, phase) in [("pending", TransactionActivityState.Phase.pending), ("cancelling", .pending),
                                ("filled", .filled), ("refunded", .refunded), ("cancelled", .cancelled), ("expired", .expired)] {
            let row = ActivityTestFixture.row(type: .limit, status: .successful,
                tracking: .init(providerKind: THORChainLimitTrackingService.providerKind, latestStatus: status))
            XCTAssertEqual(TransactionActivityPolicy.phase(for: row), phase)
        }
    }

    func testPermissionAndGenericReceiptsHaveNonemptySummaries() {
        for type in [TransactionHistoryType.approve, .trustLineActivation, .transaction, .limit] {
            let row = ActivityTestFixture.row(type: type, amountCrypto: "")
            let state = TransactionActivityPolicy.state(for: row, phase: .pending, observedAt: row.createdAt,
                revision: 1, delayed: false, showDetails: true)
            XCTAssertEqual(state.summary, "ETH")
            XCTAssertFalse(state.summary?.contains("→") == true)
        }
        let source = TransactionActivityState(phase: .sourceConfirmedOnly, observedAt: Date(), revision: 1)
        XCTAssertNil(source.staleDate)
        XCTAssertEqual(source.phase.displayStatus, .inProgress)
    }

    func testIdentityIncludesVaultAndChain() {
        let first = ActivityTestFixture.row(hash: "same", vault: "one", chain: .ethereum)
        let otherVault = ActivityTestFixture.row(hash: "same", vault: "two", chain: .ethereum)
        let otherChain = ActivityTestFixture.row(hash: "same", vault: "one", chain: .base)
        XCTAssertNotEqual(TransactionActivityPolicy.identity(first), TransactionActivityPolicy.identity(otherVault))
        XCTAssertNotEqual(TransactionActivityPolicy.identity(first), TransactionActivityPolicy.identity(otherChain))
    }

    func testLegacyTimeoutDoesNotBecomeFailed() {
        let row = ActivityTestFixture.row(status: .error, error: "timeout".localized)
        XCTAssertEqual(TransactionActivityPolicy.phase(for: row), .pending)
    }

    func testStateDerivesStaleWindowFromRowCadenceNotAFlatDefault() {
        let bitcoin = ActivityTestFixture.row(chain: .bitcoin)
        let state = TransactionActivityPolicy.state(for: bitcoin, phase: .pending, observedAt: bitcoin.createdAt,
            revision: 1, delayed: false, showDetails: true)
        XCTAssertEqual(state.staleWindow, TransactionActivityStaleness.window(for: bitcoin))
        XCTAssertGreaterThan(state.staleWindow, TransactionActivityStaleness.floor)
    }
}

enum ActivityTestFixture {
    static func row(id: UUID = UUID(), hash: String = UUID().uuidString, vault: String = "fixture-vault",
                    chain: Chain = .ethereum, type: TransactionHistoryType = .send,
                    status: TransactionHistoryStatus = .inProgress, createdAt: Date = Date(),
                    amountCrypto: String = "1 ETH", amountFiat: String = "2500",
                    fee: String = "", error: String? = nil, coinLogo: String = "", toCoinLogo: String? = nil,
                    tracking: SwapTrackingMetadataData? = nil, toCoinTicker: String? = nil,
                    toAmountCrypto: String? = nil, toAmountFiat: String? = nil,
                    toAddress: String = "0x1234567890123456789012345678901234567890") -> TransactionHistoryData {
        TransactionHistoryData(
            id: id, txHash: hash, approveTxHash: nil, pubKeyECDSA: vault, type: type, status: status,
            chainRawValue: chain.rawValue, coinTicker: "ETH", coinLogo: coinLogo, coinChainLogo: nil,
            amountCrypto: amountCrypto, amountFiat: amountFiat, fromAddress: "source",
            toAddress: toAddress,
            toCoinTicker: toCoinTicker ?? (type == .swap ? "BTC" : nil), toCoinLogo: toCoinLogo, toCoinChainLogo: nil,
            toAmountCrypto: toAmountCrypto, toAmountFiat: toAmountFiat, swapProvider: type == .swap ? "SwapKit" : nil,
            feeCrypto: fee, feeFiat: "", network: chain.rawValue, explorerLink: "", createdAt: createdAt,
            completedAt: status == .inProgress ? nil : Date(), estimatedTime: nil, errorMessage: error,
            swapTracking: tracking
        )
    }
}
