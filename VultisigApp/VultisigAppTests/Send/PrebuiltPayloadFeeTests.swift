//
//  PrebuiltPayloadFeeTests.swift
//  VultisigAppTests
//
//  A verify screen that shows a fee other than the one inside the bytes is
//  showing a number nobody will be charged. These pin the two halves of the fix:
//  a Solana payload's compute budget is part of its fee, and every other
//  pre-built flow keeps reading its own recorded total.
//

import BigInt
@testable import VultisigApp
import XCTest

final class PrebuiltPayloadFeeTests: XCTestCase {

    /// The app's flat Solana estimate plus `limit × price`. The second term is
    /// what the display ignored; the first is the app-wide figure it already
    /// had, kept so Kamino quotes on the same basis as every other Solana
    /// screen.
    func testASolanaPayloadsFeeIncludesItsInjectedComputeBudget() throws {
        let fee = try XCTUnwrap(
            PrebuiltPayloadFee.fee(
                for: solanaPayload(
                    priorityFee: BigInt(KaminoComputeBudget.fallbackUnitPriceMicroLamports),
                    priorityLimit: BigInt(KaminoComputeBudget.tokenDepositUnitLimit)
                )
            )
        )

        // 320,000 CU × 20,000 µlamports/CU = 6,400,000,000 µlamports = 6,400
        // lamports, on top of the flat estimate.
        XCTAssertEqual(fee, SolanaHelper.defaultFeeInLamports + BigInt(6_400))
    }

    /// The clamp ceiling. 0.00035 SOL is the most the compute budget can add,
    /// which is the figure the deferred finding was measured against — so the
    /// bound is on the CONTRIBUTION, not on the total, which also carries the
    /// flat base.
    func testTheComputeBudgetContributionIsBoundedByTheClamp() throws {
        let fee = try XCTUnwrap(
            PrebuiltPayloadFee.fee(
                for: solanaPayload(
                    priorityFee: BigInt(KaminoComputeBudget.maxUnitPriceMicroLamports),
                    priorityLimit: BigInt(KaminoComputeBudget.nativeDepositUnitLimit)
                )
            )
        )

        XCTAssertEqual(fee, SolanaHelper.defaultFeeInLamports + BigInt(350_000))
        XCTAssertLessThanOrEqual(fee - SolanaHelper.defaultFeeInLamports, BigInt(350_000))
    }

    /// Rounding up rather than down: the network charges whole lamports, and a
    /// fee row that rounded toward zero would under-report the charge for the
    /// same reason it exists.
    func testAFractionalLamportOfPriorityFeeRoundsUp() throws {
        let fee = try XCTUnwrap(
            PrebuiltPayloadFee.fee(for: solanaPayload(priorityFee: BigInt(1), priorityLimit: BigInt(1)))
        )

        XCTAssertEqual(fee, SolanaHelper.defaultFeeInLamports + BigInt(1))
    }

    /// A Solana payload with no compute budget — every non-Kamino raw payload —
    /// reads exactly as it did before.
    func testASolanaPayloadWithoutAComputeBudgetIsUnchanged() throws {
        let fee = try XCTUnwrap(
            PrebuiltPayloadFee.fee(for: solanaPayload(priorityFee: .zero, priorityLimit: .zero))
        )

        XCTAssertEqual(fee, SolanaHelper.defaultFeeInLamports)
    }

    /// Other chains' pre-built payloads carry their own total, so it is used
    /// verbatim — an EVM payload's is `maxFeePerGas × gasLimit`.
    func testAnEvmPayloadReportsItsOwnRecordedTotal() throws {
        let fee = try XCTUnwrap(
            PrebuiltPayloadFee.fee(
                for: payload(
                    chain: .ethereum,
                    chainSpecific: .Ethereum(
                        maxFeePerGasWei: BigInt(30),
                        priorityFeeWei: BigInt(1),
                        nonce: 0,
                        gasLimit: BigInt(21_000)
                    )
                )
            )
        )

        XCTAssertEqual(fee, BigInt(630_000))
    }

    /// A payload built without a fee estimate must not replace the caller's own
    /// estimate with a zero.
    func testAZeroRecordedFeeFallsBackToTheCallersEstimate() {
        XCTAssertNil(
            PrebuiltPayloadFee.fee(
                for: payload(
                    chain: .ethereum,
                    chainSpecific: .Ethereum(
                        maxFeePerGasWei: .zero,
                        priorityFeeWei: .zero,
                        nonce: 0,
                        gasLimit: .zero
                    )
                )
            )
        )
    }

    // MARK: - Helpers

    private func solanaPayload(priorityFee: BigInt, priorityLimit: BigInt) -> KeysignPayload {
        payload(
            chain: .solana,
            chainSpecific: .Solana(
                recentBlockHash: "",
                priorityFee: priorityFee,
                priorityLimit: priorityLimit,
                fromAddressPubKey: nil,
                toAddressPubKey: nil,
                hasProgramId: false
            )
        )
    }

    private func payload(chain: Chain, chainSpecific: BlockChainSpecific) -> KeysignPayload {
        KeysignPayload(
            coin: Coin(
                asset: CoinMeta(
                    chain: chain,
                    ticker: chain.ticker,
                    logo: "logo",
                    decimals: 9,
                    priceProviderId: "id",
                    contractAddress: "",
                    isNativeToken: true
                ),
                address: "address",
                hexPublicKey: ""
            ),
            toAddress: "to",
            toAmount: .zero,
            chainSpecific: chainSpecific,
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "ecdsa",
            vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            kaminoPayload: nil,
            skipBroadcast: false,
            signData: nil
        )
    }
}
