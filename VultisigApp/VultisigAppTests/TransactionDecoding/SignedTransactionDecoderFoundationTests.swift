//
//  SignedTransactionDecoderFoundationTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import VultisigCommonData
import XCTest

final class SignedTransactionDecoderFoundationTests: XCTestCase {

    func testRegistryStartsEmpty() {
        XCTAssertTrue(SignedTransactionDecoder.decoders.isEmpty)
    }

    func testUnregisteredContentIsUnreadable() {
        let decoded = SignedTransactionDecoder.decode(StubContent())

        XCTAssertEqual(decoded, .unreadable)
        XCTAssertEqual(decoded.operation, .unknown)
        XCTAssertEqual(decoded.amount, .unstated)
        XCTAssertEqual(decoded.evidence, .unread)
    }

    func testOpaqueSignedContentWithholdsEverySidecar() {
        let content = StubContent(hasOpaqueSignedContent: true)

        XCTAssertNil(content.corroborated)
    }

    func testCorroboratedContentKeepsCommittedFieldsTogether() {
        let content = StubContent(hasOpaqueSignedContent: false)
        let corroborated = content.corroborated

        XCTAssertEqual(corroborated?.toAddress, "destination")
        XCTAssertEqual(corroborated?.amount, .committed(BigInt(42)))
        XCTAssertEqual(
            corroborated?.memo(.memoIsInertWhenRoutedEarlier),
            "memo"
        )
    }

    func testEvidenceStrengthFollowsSignedProvenance() {
        XCTAssertTrue(DecodedEvidence.signedData.isNoWeaker(than: .memo))
        XCTAssertTrue(DecodedEvidence.memo.isNoWeaker(than: .structuredPayload))
        XCTAssertFalse(DecodedEvidence.unread.isNoWeaker(than: .signedData))
    }
}

private extension SignedTransactionDecoderFoundationTests {

    struct StubContent: SignedTransactionContent {
        let chain: Chain = .ton
        let isNativeCoin = true
        let rawToAddress = "destination"
        let rawAmount = SignedAmount.committed(BigInt(42))
        let signedData: SignData? = nil
        let hasOpaqueSignedContent: Bool
        let rawMemo: String? = "memo"
        let rawTransactionType = VSTransactionType.unspecified
        let rawWasmPayload: WasmExecuteContractPayload? = nil
        let rawSwap: SwapPayload? = nil
        let rawApprove: ERC20ApprovePayload? = nil
        let stakingIntent: SolanaStakingPayload? = nil
        let cosmosStakingIntent: CosmosStakingPayload? = nil

        init(hasOpaqueSignedContent: Bool = false) {
            self.hasOpaqueSignedContent = hasOpaqueSignedContent
        }
    }
}
