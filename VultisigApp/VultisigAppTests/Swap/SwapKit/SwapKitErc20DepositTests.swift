//
//  SwapKitErc20DepositTests.swift
//  VultisigAppTests
//
//  ERC-20 source via SwapKit NEAR-Intents (`txHint: simpleTransfer`): the
//  `/v3/swap` tx calls the sold token with `transfer(targetAddress, amount)`.
//  It needs no approve (a transfer spends no allowance, and an approve to the
//  deposit address would outlive the swap), and it must transfer exactly the
//  sold amount to `targetAddress` with no native value.
//
//  `v3-real-usdt-sol-swap.json` is the live `/v3/swap` response captured
//  2026-10-03T14:59Z through the app's proxy (20 USDT -> SOL, NEAR provider):
//
//    curl -X POST https://api.vultisig.com/swapkit/v3/quote \
//      -H 'Content-Type: application/json' -H 'Referer: vultisig-ios' \
//      -d '{"sellAsset":"ETH.USDT-0xdAC17F958D2ee523a2206206994597C13D831ec7","buyAsset":"SOL.SOL",
//           "sellAmount":"20","sourceAddress":"0x28C6c06298d514Db089934071355E5743bf21d60",
//           "destinationAddress":"9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
//           "slippage":1,"providers":["NEAR"],"affiliateFee":50}'
//    curl -X POST https://api.vultisig.com/swapkit/v3/swap \
//      -H 'Content-Type: application/json' -H 'Referer: vultisig-ios' \
//      -d '{"routeId":"5f49acb2-109b-475a-ab61-7091ccd374a6",
//           "sourceAddress":"0x28C6c06298d514Db089934071355E5743bf21d60",
//           "destinationAddress":"9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"}'
//

import BigInt
import Foundation
import XCTest
@testable import VultisigApp

@MainActor
final class SwapKitErc20DepositTests: XCTestCase {

    private static let usdtContract = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
    private static let soldAmount = BigInt(20_000_000)

    private func usdt() -> Coin {
        let meta = CoinMeta(
            chain: .ethereum,
            ticker: "USDT",
            logo: "usdt",
            decimals: 6,
            priceProviderId: "tether",
            contractAddress: Self.usdtContract,
            isNativeToken: false
        )
        return Coin(asset: meta, address: "0x28C6c06298d514Db089934071355E5743bf21d60", hexPublicKey: "")
    }

    private func liveResponse(mutating mutate: (inout [String: Any]) -> Void = { _ in }) throws -> SwapKitSwapResponse {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: SwapKitFixtureLoader.loadData("v3-real-usdt-sol-swap")) as? [String: Any]
        )
        mutate(&json)
        return try JSONDecoder().decode(SwapKitSwapResponse.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func replacingTx(_ json: inout [String: Any], _ key: String, _ value: String) {
        var tx = json["tx"] as? [String: Any] ?? [:]
        tx[key] = value
        json["tx"] = tx
    }

    func testLiveUsdtDepositIsAnErc20DepositTransferThatNeedsNoApprove() throws {
        let response = try liveResponse()
        let quote = SwapQuote.swapkit(response, fee: nil, subProvider: "NEAR")

        XCTAssertTrue(response.isErc20DepositTransfer(fromCoin: usdt()))
        XCTAssertNoThrow(try response.validateErc20DepositTransfer(fromCoin: usdt(), amount: Self.soldAmount))
        XCTAssertFalse(SwapCryptoLogic.isApproveRequired(fromCoin: usdt(), quote: quote))
        XCTAssertNil(try SwapCryptoLogic.approveSpender(fromCoin: usdt(), quote: quote))
    }

    func testRefusesATransferOfAnotherAmount() throws {
        XCTAssertThrowsError(try liveResponse().validateErc20DepositTransfer(fromCoin: usdt(), amount: Self.soldAmount + 1))
    }

    func testRefusesATransferToAnotherRecipient() throws {
        let other = "0x2222222222222222222222222222222222222222"
        let data = "0xa9059cbb" + String(repeating: "0", count: 24) + other.dropFirst(2)
            + String(Self.soldAmount, radix: 16).leftPad(to: 64)
        let response = try liveResponse { self.replacingTx(&$0, "data", data) }
        XCTAssertThrowsError(try response.validateErc20DepositTransfer(fromCoin: usdt(), amount: Self.soldAmount))
    }

    func testRefusesNativeValueAndNonTransferCalls() throws {
        let withValue = try liveResponse { self.replacingTx(&$0, "value", "0x1") }
        XCTAssertThrowsError(try withValue.validateErc20DepositTransfer(fromCoin: usdt(), amount: Self.soldAmount))

        let approve = try liveResponse { json in
            let data = (json["tx"] as? [String: Any])?["data"] as? String ?? ""
            self.replacingTx(&json, "data", data.replacingOccurrences(of: "0xa9059cbb", with: "0x095ea7b3"))
        }
        XCTAssertThrowsError(try approve.validateErc20DepositTransfer(fromCoin: usdt(), amount: Self.soldAmount))
    }

    func testARouterCallFromATokenIsNotADepositTransfer() throws {
        let routed = try liveResponse { self.replacingTx(&$0, "to", "0x111111125421ca6dc452d289314280a0f8842a65") }
        XCTAssertFalse(routed.isErc20DepositTransfer(fromCoin: usdt()))
    }

    func testPayloadBuilderBindsTheDepositToTheSoldAmount() async throws {
        let quote = SwapQuote.swapkit(try liveResponse(), fee: nil, subProvider: "NEAR")

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            transaction: transaction(fromAmount: 20, quote: quote),
            chainSpecific: ethereumChainSpecific(),
            vault: vault()
        )
        XCTAssertNil(payload.approvePayload)
        guard case let .generic(generic) = payload.swapPayload else {
            return XCTFail("Expected .generic swapPayload")
        }
        XCTAssertEqual(generic.quote.tx.to, Self.usdtContract)

        do {
            _ = try await SwapCryptoLogic.buildSwapKeysignPayload(
                transaction: transaction(fromAmount: 21, quote: quote),
                chainSpecific: ethereumChainSpecific(),
                vault: vault()
            )
            XCTFail("A deposit transferring 20 USDT must not sign as a 21 USDT swap")
        } catch {
            guard case .swapKitDepositRefused = error as? EVMSwapTxGuardError else {
                return XCTFail("Expected swapKitDepositRefused, got \(error)")
            }
        }
    }

    /// The co-signer never sees the quote, only the relayed payload, and screens
    /// nothing but `tx.to`, which for a deposit is the token. It must re-derive
    /// the deposit from the calldata it signs.
    func testCoSignerBindsTheDepositCalldataBeforeSigning() throws {
        let live = try liveResponse()
        guard case .evm(let tx) = live.tx else { return XCTFail("Expected an EVM tx") }
        let usdc = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
        let approveToSameRecipient = tx.data.replacingOccurrences(of: "0xa9059cbb", with: "0x095ea7b3")

        XCTAssertNoThrow(try coSignerMessages(to: tx.to, data: tx.data, value: "0", fromAmount: Self.soldAmount))
        assertCoSignerRefuses(to: tx.to, data: tx.data, value: "0", fromAmount: Self.soldAmount + 1)
        assertCoSignerRefuses(to: usdc, data: tx.data, value: "0", fromAmount: Self.soldAmount)
        assertCoSignerRefuses(to: tx.to, data: tx.data, value: "1", fromAmount: Self.soldAmount)
        assertCoSignerRefuses(to: tx.to, data: approveToSameRecipient, value: "0", fromAmount: Self.soldAmount)
    }

    /// Builds the joiner's messages the way `JoinKeysignViewModel` does, from a
    /// relayed SwapKit payload selling 20 USDT.
    private func coSignerMessages(to: String, data: String, value: String, fromAmount: BigInt) throws -> [String] {
        let sol = Coin(asset: CoinMeta.make(chain: .solana, ticker: "SOL", decimals: 9, isNativeToken: true), address: "", hexPublicKey: "")
        let swap = GenericSwapPayload(
            fromCoin: usdt(),
            toCoin: sol,
            fromAmount: fromAmount,
            toAmountDecimal: 0,
            quote: EVMQuote(
                dstAmount: "0",
                tx: EVMQuote.Transaction(from: usdt().address, to: to, data: data, value: value, gasPrice: "1", gas: 76_837)
            ),
            provider: .swapkit
        )
        let keysign = KeysignPayload(
            coin: usdt(),
            toAddress: "0xCB2aC797EFf13Ee982453F5722B74aB5c56741Af",
            toAmount: fromAmount,
            chainSpecific: ethereumChainSpecific(),
            utxos: [],
            memo: nil,
            swapPayload: .generic(swap),
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
        return try KeysignMessageFactory(payload: keysign, vaultPubKeyEdDSA: "").getKeysignMessages()
    }

    private func assertCoSignerRefuses(to: String, data: String, value: String, fromAmount: BigInt, line: UInt = #line) {
        XCTAssertThrowsError(try coSignerMessages(to: to, data: data, value: value, fromAmount: fromAmount), line: line) {
            guard case .swapKitDepositRefused = $0 as? EVMSwapTxGuardError else {
                return XCTFail("Expected swapKitDepositRefused, got \($0)", line: line)
            }
        }
    }

    /// SwapKit states 900k gas for this route; the deposit is a token send
    /// simulated at 120k. The relayed payload must not carry SwapKit's figure,
    /// since every platform signs max(quote gas, gasLimit), and the bond the
    /// initiator shows and validates must be the one signed.
    func testDepositGasIsNotRaisedBySwapKitsRouteFigure() async throws {
        let quote = SwapQuote.swapkit(try liveResponse { self.replacingTx(&$0, "gas", "0xdbba0") }, fee: nil, subProvider: "NEAR")
        let maxFeePerGas = BigInt(2_000_000_000)
        let simulated = BigInt(120_000)
        let transaction = transaction(fromAmount: 20, quote: quote, gas: maxFeePerGas, gasLimit: simulated)

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            transaction: transaction,
            chainSpecific: ethereumChainSpecific(),
            vault: vault()
        )
        guard case let .generic(generic) = payload.swapPayload else {
            return XCTFail("Expected .generic swapPayload")
        }
        let signed = EVMSwapFee.effective(
            quoteGasPriceWei: EVMSwapFee.quoteGasPriceWei(generic.quote.tx.gasPrice),
            quoteGas: BigInt(generic.quote.tx.gas),
            maxFeePerGasWei: maxFeePerGas,
            gasLimit: simulated
        )
        XCTAssertEqual(signed.gasLimit, simulated)
        XCTAssertEqual(transaction.displayedNetworkFeeWei, maxFeePerGas * simulated)
    }

    private func transaction(fromAmount: Decimal, quote: SwapQuote, gas: BigInt = 0, gasLimit: BigInt = 0) -> SwapTransaction {
        let eth = Coin(asset: CoinMeta.make(chain: .ethereum, ticker: "ETH", decimals: 18, isNativeToken: true), address: usdt().address, hexPublicKey: "")
        let sol = Coin(asset: CoinMeta.make(chain: .solana, ticker: "SOL", decimals: 9, isNativeToken: true), address: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM", hexPublicKey: "")
        return SwapTransaction(
            fromCoin: usdt(),
            toCoin: sol,
            fromAmount: fromAmount,
            kind: .market(quote),
            gas: gas,
            gasLimit: gasLimit,
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: eth,
            advancedSettings: .default
        )
    }

    private func vault() -> Vault {
        Vault(
            name: "Test Vault",
            signers: [],
            pubKeyECDSA: "test-pub-ecdsa",
            pubKeyEdDSA: "test-pub-eddsa",
            keyshares: [],
            localPartyID: "party",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
    }

    private func ethereumChainSpecific() -> BlockChainSpecific {
        .Ethereum(maxFeePerGasWei: BigInt(2_000_000_000), priorityFeeWei: BigInt(1_000_000_000), nonce: 1, gasLimit: BigInt(120_000))
    }
}

private extension String {
    func leftPad(to length: Int) -> String {
        String(repeating: "0", count: max(0, length - count)) + self
    }
}

@MainActor
final class SwapKitErc20DepositGasTests: XCTestCase {
    /// An ERC-20 deposit is sized like a token send (live simulation ~48k), not
    /// like a router swap (600k, then +50% swap inflation = 900k).
    func testDepositTransferGasIsTheSimulationRaisedToTheErc20Floor() {
        XCTAssertEqual(BlockChainService.erc20DepositTransferGasLimit(estimated: 48_000), 120_000)
        XCTAssertEqual(BlockChainService.erc20DepositTransferGasLimit(estimated: 150_000), 150_000)
        XCTAssertEqual(BlockChainService.erc20DepositTransferGasLimit(estimated: nil), 120_000)
    }
}
