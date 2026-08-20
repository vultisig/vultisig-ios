//
//  DecoderInertnessTests.swift
//  VultisigAppTests
//
//  Pins the exact registry and verifies that unsupported chains stay inert.
//

@testable import VultisigApp
import BigInt
import XCTest

final class DecoderInertnessTests: XCTestCase {

    /// Pins reader types because some establish provenance without fixed chains.
    func testTheRegistryContainsExactlyTheExpectedReaders() {
        XCTAssertEqual(
            SignedTransactionDecoder.decoders.map { String(describing: type(of: $0)) },
            [
                "SolanaTransactionDecoder",
                "CosmosSignDocDecoder",
                "TronTransactionDecoder",
                "THORChainTransactionDecoder",
                "TonTransactionDecoder",
                "CosmosTransactionDecoder",
                "MayaChainTransactionDecoder"
            ],
            "a chain reader was registered or removed without saying so here"
        )
    }

    /// Swap owns custom Done content; the normal-send surfaces use the decoder.
    func testTheDecodedProviderSpeaksOnVerifyAndNormalSendDone() {
        XCTAssertEqual(
            TransactionHeroProvider.decoded.surfaces,
            [.functionCallVerify, .sendVerify, .sendDone, .keysignConfirm, .keysignDone]
        )
    }

    /// Uses a real payload so the resolver reaches the decoder path.
    func testAnOrdinaryPayloadResolvesNoHeroOnAnySurface() {
        let payload = Self.benignPayload()

        for surface in TransactionHeroSurface.allCases {
            XCTAssertNil(
                TransactionHeroResolver.hero(
                    on: surface,
                    for: .cosigning(payload: payload, simulated: { nil })
                ),
                "\(surface) resolved a hero for an ordinary transfer while no chain reader is registered"
            )
        }
    }

    /// Simulation remains unchanged while decoding is inert.
    func testASimulatedHeroSurvivesUnchanged() {
        let payload = Self.benignPayload()
        let simulated = HeroContent.send(
            title: "Transfer",
            coin: HeroCoinAmount(amount: "1", ticker: "TON", logo: "ton")
        )

        for surface in [TransactionHeroSurface.keysignConfirm, .keysignDone] {
            XCTAssertEqual(
                TransactionHeroResolver.hero(
                    on: surface,
                    for: .cosigning(payload: payload, simulated: { simulated })
                ),
                simulated,
                "\(surface) altered the simulation's hero while no chain reader is registered"
            )
        }
    }

    /// An ordinary TON transfer that no decoder should claim.
    private static func benignPayload() -> KeysignPayload {
        KeysignPayload(
            coin: Coin(
                asset: CoinMeta(
                    chain: .ton,
                    ticker: "TON",
                    logo: "ton",
                    decimals: 9,
                    priceProviderId: "the-open-network",
                    contractAddress: "",
                    isNativeToken: true
                ),
                address: "EQfrom",
                hexPublicKey: "00"
            ),
            toAddress: "EQto",
            toAmount: BigInt(1_000_000_000),
            chainSpecific: .Ton(sequenceNumber: 1, expireAt: 0, bounceable: true, sendMaxAmount: false),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "pub",
            vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }

    /// An unreadable result carries no operation, quantity, or evidence.
    func testAnUnreadDecodingStatesNothing() {
        let unreadable = DecodedTransaction.unreadable
        XCTAssertEqual(unreadable.operation, .unknown)
        XCTAssertEqual(unreadable.amount, .unstated)
        XCTAssertEqual(unreadable.evidence, .unread)
        XCTAssertNil(
            DecodedTransactionPresentation.title(for: unreadable.operation),
            "`.unknown` must never carry a verb — that is the whole difference between describing and guessing"
        )
    }
}
