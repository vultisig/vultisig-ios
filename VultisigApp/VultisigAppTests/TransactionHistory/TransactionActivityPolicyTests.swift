import Foundation
import XCTest
@testable import VultisigApp

@MainActor
final class TransactionActivityPolicyTests: XCTestCase {
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
}

enum ActivityTestFixture {
    static func row(id: UUID = UUID(), hash: String = UUID().uuidString, vault: String = "fixture-vault",
                    chain: Chain = .ethereum, type: TransactionHistoryType = .send,
                    status: TransactionHistoryStatus = .inProgress, createdAt: Date = Date(),
                    amountCrypto: String = "1 ETH", amountFiat: String = "2500",
                    fee: String = "", error: String? = nil, coinLogo: String = "", toCoinLogo: String? = nil,
                    tracking: SwapTrackingMetadataData? = nil) -> TransactionHistoryData {
        TransactionHistoryData(
            id: id, txHash: hash, approveTxHash: nil, pubKeyECDSA: vault, type: type, status: status,
            chainRawValue: chain.rawValue, coinTicker: "ETH", coinLogo: coinLogo, coinChainLogo: nil,
            amountCrypto: amountCrypto, amountFiat: amountFiat, fromAddress: "source",
            toAddress: "0x1234567890123456789012345678901234567890",
            toCoinTicker: type == .swap ? "BTC" : nil, toCoinLogo: toCoinLogo, toCoinChainLogo: nil,
            toAmountCrypto: nil, toAmountFiat: nil, swapProvider: type == .swap ? "SwapKit" : nil,
            feeCrypto: fee, feeFiat: "", network: chain.rawValue, explorerLink: "", createdAt: createdAt,
            completedAt: status == .inProgress ? nil : Date(), estimatedTime: nil, errorMessage: error,
            swapTracking: tracking
        )
    }
}
