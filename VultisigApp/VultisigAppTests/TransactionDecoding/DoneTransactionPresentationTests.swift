//
//  DoneTransactionPresentationTests.swift
//  VultisigAppTests
//

import BigInt
@testable import VultisigApp
import WalletCore
import XCTest

@MainActor
final class DoneTransactionPresentationTests: XCTestCase {

    private struct StubReader: PositionReading {
        let value: HeroCoinAmount?
        func handles(_: DecodedTransaction, coin _: Coin) -> Bool { true }
        func amount(for _: DecodedTransaction, coin _: Coin) -> HeroCoinAmount? { value }
    }

    func testExactStakeUsesPastVerbAndSignedAmount() throws {
        let payload = Self.tronPayload(memo: "FREEZE:ENERGY")
        let hero = try XCTUnwrap(
            DoneTransactionPresentation.hero(for: payload, trustedCoins: [payload.coin])
        )

        guard case .send(let title, let amount) = hero else {
            return XCTFail("a stated stake must keep its exact amount")
        }
        XCTAssertEqual(title, "doneVerbStaked".localized)
        XCTAssertEqual(amount.amount, "5")
        XCTAssertEqual(amount.ticker, "TRX")
    }

    func testTonStakeUsesPastVerbAndCuratedNativeAmount() throws {
        let payload = Self.tonStakePayload()
        let hero = try XCTUnwrap(
            DoneTransactionPresentation.hero(for: payload, trustedCoins: [payload.coin])
        )

        guard case .send(let title, let amount) = hero else {
            return XCTFail("a TON deposit must keep its exact signed amount")
        }
        XCTAssertEqual(title, "doneVerbStaked".localized)
        XCTAssertEqual(amount.amount, "1")
        XCTAssertEqual(amount.ticker, TokensStore.nativeAsset(for: .ton)?.ticker)
    }

    func testSolanaDelegateProducesSameProjectedDoneDataForBothPaths() async throws {
        let payload = try Self.solanaDelegatePayload()
        let projected = HeroCoinAmount(amount: "2", ticker: "SOL", logo: "solana")

        let initiator = await DoneTransactionPresentation.resolve(
            for: payload,
            trustedCoins: [payload.coin],
            readers: [StubReader(value: projected)]
        )
        let cosigner = await DoneTransactionPresentation.resolve(
            for: payload,
            trustedCoins: [payload.coin],
            readers: [StubReader(value: projected)]
        )

        XCTAssertEqual(initiator, cosigner)
        let display = DoneHeroDisplay(
            input: Self.donePayload(coin: payload.coin, operationHero: initiator)
        )
        XCTAssertEqual(display.verb, "doneVerbDelegated".localized)
        XCTAssertEqual(display.crypto, "≈ 2 SOL")
    }

    func testUnknownTransactionKeepsTheExistingSentFallback() {
        let payload = Self.tronPayload(memo: nil)
        XCTAssertNil(DoneTransactionPresentation.hero(for: payload, trustedCoins: [payload.coin]))
        XCTAssertNil(DoneTransactionPresentation.specificTitle(for: payload))
    }

    func testProjectedAmountUsesPastVerbAndRemainsApproximate() async throws {
        let payload = Self.tcyUnstakePayload()
        let hero = await DoneTransactionPresentation.resolve(
            for: payload,
            trustedCoins: [payload.coin],
            readers: [StubReader(value: HeroCoinAmount(amount: "1,002.57", ticker: "TCY", logo: "tcy"))]
        )

        guard case .projected(let title, let estimate, _) = hero else {
            return XCTFail("expected a projected Done hero")
        }
        XCTAssertEqual(title, "doneVerbUnstaked".localized)
        XCTAssertEqual(estimate?.amount, "1,002.57")

        let input = Self.donePayload(coin: payload.coin, operationHero: hero)
        XCTAssertEqual(DoneHeroDisplay(input: input).crypto, "≈ 1,002.57 TCY")
    }

    func testMissingProjectionNeverFallsBackToTheCarrierAmount() {
        let ton = Self.coin(chain: .ton, ticker: "TON", decimals: 9)
        let hero = HeroContent.projected(
            title: "doneVerbUnstaked".localized,
            estimate: nil,
            scope: "your whole stake"
        )
        let input = TransactionDonePayload(
            coin: ton,
            amountCrypto: "0.2 TON",
            amountFiat: "1.00",
            operationHero: hero,
            hash: "hash",
            explorerLink: "",
            memo: "w",
            isSend: true,
            fromAddress: "from",
            toAddress: "pool",
            fee: FeeDisplay(crypto: "", fiat: ""),
            keysignPayload: nil,
            pubKeyECDSA: "pub"
        )

        let display = DoneHeroDisplay(input: input)
        XCTAssertEqual(display.verb, "doneVerbUnstaked".localized)
        XCTAssertEqual(display.crypto, "TON")
        XCTAssertNil(display.fiat)
        XCTAssertNotEqual(display.crypto, "0.2 TON")
    }

    func testNormalSendPreservesItsExistingAmountAndUsesSent() {
        let coin = Self.coin(chain: .ethereum, ticker: "ETH", decimals: 18)
        let input = Self.donePayload(coin: coin, operationHero: nil)
        let display = DoneHeroDisplay(input: input)

        XCTAssertEqual(display.verb, "doneVerbSent".localized)
        XCTAssertEqual(display.crypto, "1.5 ETH")
        XCTAssertEqual(display.logo, coin.logo)
        XCTAssertEqual(display.tokenChainLogo, coin.tokenChainLogo)
    }

    func testVerifyProjectionCanBeRetitledWithoutChangingItsFigure() throws {
        let payload = Self.tcyUnstakePayload()
        let verify = HeroContent.projected(
            title: "youreUnstaking".localized,
            estimate: HeroCoinAmount(amount: "10", ticker: "TCY", logo: "tcy"),
            scope: "50%"
        )

        let done = try XCTUnwrap(
            DoneTransactionPresentation.retitleResolvedHero(verify, for: payload)
        )
        guard case .projected(let title, let estimate, let scope) = done else {
            return XCTFail("retitling changed the projection shape")
        }
        XCTAssertEqual(title, "doneVerbUnstaked".localized)
        XCTAssertEqual(estimate?.amount, "10")
        XCTAssertEqual(scope, "50%")
    }

    private static func donePayload(
        coin: Coin,
        operationHero: HeroContent?
    ) -> TransactionDonePayload {
        TransactionDonePayload(
            coin: coin,
            amountCrypto: "1.5 \(coin.ticker)",
            amountFiat: "5000",
            operationHero: operationHero,
            hash: "hash",
            explorerLink: "",
            memo: "",
            isSend: true,
            fromAddress: "from",
            toAddress: "to",
            fee: FeeDisplay(crypto: "", fiat: ""),
            keysignPayload: nil,
            pubKeyECDSA: "pub"
        )
    }

    private static func coin(chain: Chain, ticker: String, decimals: Int) -> Coin {
        Coin(
            asset: CoinMeta(
                chain: chain,
                ticker: ticker,
                logo: ticker.lowercased(),
                decimals: decimals,
                priceProviderId: ticker.lowercased(),
                contractAddress: "",
                isNativeToken: true
            ),
            address: "owner",
            hexPublicKey: "00"
        )
    }

    private static func tronPayload(memo: String?) -> KeysignPayload {
        let coin = coin(chain: .tron, ticker: "TRX", decimals: 6)
        return KeysignPayload(
            coin: coin,
            toAddress: coin.address,
            toAmount: BigInt(5_000_000),
            chainSpecific: .Tron(
                timestamp: 0,
                expiration: 0,
                blockHeaderTimestamp: 0,
                blockHeaderNumber: 0,
                blockHeaderVersion: 0,
                blockHeaderTxTrieRoot: "",
                blockHeaderParentHash: "",
                blockHeaderWitnessAddress: "",
                gasFeeEstimation: 0
            ),
            utxos: [],
            memo: memo,
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

    private static func tcyUnstakePayload() -> KeysignPayload {
        let coin = Coin(asset: TokensStore.tcy, address: "thor1owner", hexPublicKey: "00")
        return KeysignPayload(
            coin: coin,
            toAddress: "thor1destination",
            toAmount: .zero,
            chainSpecific: .THORChain(accountNumber: 0, sequence: 0, fee: 0, isDeposit: true),
            utxos: [],
            memo: "tcy-:5006",
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

    private static func tonStakePayload() -> KeysignPayload {
        let coin = coin(chain: .ton, ticker: "TON", decimals: 9)
        return KeysignPayload(
            coin: coin,
            toAddress: "EQpool",
            toAmount: BigInt(1_000_000_000),
            chainSpecific: .Ton(sequenceNumber: 1, expireAt: 0, bounceable: true, sendMaxAmount: false),
            utxos: [],
            memo: "d",
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

    private static func solanaDelegatePayload() throws -> KeysignPayload {
        let ownerKey = try XCTUnwrap(PrivateKey(data: Data(repeating: 0x31, count: 32)))
        let ownerPublicKey = ownerKey.getPublicKeyEd25519()
        let validatorKey = try XCTUnwrap(PrivateKey(data: Data(repeating: 0x37, count: 32)))
        let validator = AnyAddress(
            publicKey: validatorKey.getPublicKeyEd25519(),
            coin: .solana
        ).description
        let coin = Coin(
            asset: CoinMeta(
                chain: .solana,
                ticker: "SOL",
                logo: "solana",
                decimals: 9,
                priceProviderId: "solana",
                contractAddress: "",
                isNativeToken: true
            ),
            address: AnyAddress(publicKey: ownerPublicKey, coin: .solana).description,
            hexPublicKey: ownerPublicKey.data.hexString
        )
        let payload = KeysignPayload(
            coin: coin,
            toAddress: validator,
            toAmount: BigInt(2_100_000_000),
            chainSpecific: .Solana(
                recentBlockHash: "11111111111111111111111111111111",
                priorityFee: 0,
                priorityLimit: 0,
                fromAddressPubKey: nil,
                toAddressPubKey: nil,
                hasProgramId: false
            ),
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
            solanaStakingPayload: .delegate(votePubkey: validator, lamports: 2_100_000_000),
            skipBroadcast: false,
            signData: nil
        )
        let raw = try SolanaHelper.buildStakingUnsignedTransaction(keysignPayload: payload)
        return payload.withSignData(.signSolana(SignSolana(rawTransactions: [raw])))
    }
}
