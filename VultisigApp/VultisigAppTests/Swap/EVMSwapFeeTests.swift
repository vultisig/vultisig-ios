//
//  EVMSwapFeeTests.swift
//  VultisigAppTests
//
//  `EVMSwapFee` is the single source of truth for the gas parameters an EVM
//  aggregator/SwapKit swap is signed with. The first half covers the pure
//  reconciliation branches; the second half is the anti-drift pin — the
//  pre-image hash the signer (`OneInchSwaps`) commits to must equal the hash
//  of a transaction priced with the calculator's outputs, for every branch of
//  the reconciliation. If the signer's formula ever drifts from the
//  calculator, these fire.
//

import BigInt
import WalletCore
import XCTest
@testable import VultisigApp

@MainActor
final class EVMSwapFeeTests: XCTestCase {

    private let oneGwei = BigInt(1_000_000_000)

    // MARK: - Reconciliation branches

    func testEffectiveBumpsStaleQuoteGasPriceToOracleCeiling() {
        let effective = EVMSwapFee.effective(
            quoteGasPriceWei: oneGwei / 2,
            quoteGas: BigInt(359_942),
            maxFeePerGasWei: oneGwei,
            gasLimit: BigInt(40_000)
        )
        XCTAssertEqual(effective.gasPriceWei, oneGwei, "A stale provider gas price must be bumped to the oracle ceiling")
        XCTAssertEqual(effective.gasLimit, BigInt(359_942))
    }

    func testEffectiveKeepsQuoteGasPriceWhenAboveOracle() {
        let effective = EVMSwapFee.effective(
            quoteGasPriceWei: 3 * oneGwei,
            quoteGas: BigInt(359_942),
            maxFeePerGasWei: oneGwei,
            gasLimit: BigInt(40_000)
        )
        XCTAssertEqual(effective.gasPriceWei, 3 * oneGwei, "A provider pricing above the oracle wins the max")
    }

    func testEffectiveFloorsRouteGasWithOracleGasLimit() {
        let effective = EVMSwapFee.effective(
            quoteGasPriceWei: oneGwei,
            quoteGas: BigInt(210_000),
            maxFeePerGasWei: oneGwei,
            gasLimit: BigInt(900_000)
        )
        XCTAssertEqual(effective.gasLimit, BigInt(900_000), "The oracle gas limit floors an under-reporting route")
    }

    func testEffectiveUsesRouteGasWhenAboveOracleGasLimit() {
        let effective = EVMSwapFee.effective(
            quoteGasPriceWei: oneGwei,
            quoteGas: BigInt(359_942),
            maxFeePerGasWei: oneGwei,
            gasLimit: BigInt(40_000)
        )
        XCTAssertEqual(effective.gasLimit, BigInt(359_942), "A route gas above the stored floor is what gets signed")
    }

    func testEffectiveZeroQuoteGasFallsBackToDefaultSwapGasUnit() {
        let effective = EVMSwapFee.effective(
            quoteGasPriceWei: oneGwei,
            quoteGas: .zero,
            maxFeePerGasWei: oneGwei,
            gasLimit: BigInt(40_000)
        )
        XCTAssertEqual(
            effective.gasLimit,
            BigInt(EVMHelper.defaultETHSwapGasUnit),
            "A quote that omits its gas falls back to the 600k default, exactly like the signer"
        )
    }

    func testFeeWeiIsTheBondOfEffectiveGasPriceAndLimit() {
        let effective = EVMSwapFee.Effective(gasPriceWei: 2 * oneGwei, gasLimit: BigInt(500_000))
        XCTAssertEqual(effective.feeWei, 2 * oneGwei * BigInt(500_000))
    }

    func testQuoteGasPriceWeiParsesDecimalString() {
        XCTAssertEqual(EVMSwapFee.quoteGasPriceWei("568000000"), BigInt(568_000_000))
    }

    func testQuoteGasPriceWeiUnparseableBecomesZero() {
        XCTAssertEqual(EVMSwapFee.quoteGasPriceWei("0x2aaa0b23"), .zero, "Hex-prefixed input is not a decimal wei string")
        XCTAssertEqual(EVMSwapFee.quoteGasPriceWei(""), .zero)
    }

    // MARK: - Anti-drift pin: the signer commits exactly the calculator's outputs

    func testSignerCommitsCalculatorOutputsWhenQuoteGasPriceAboveOracle() throws {
        try assertSignerMatchesCalculator(
            chain: .ethereum,
            quoteGasPrice: "2000000000", // 2 Gwei, above the 1 Gwei oracle
            quoteGas: 500_000,
            maxFeePerGasWei: oneGwei,
            gasLimit: BigInt(400_000),
            expectedGasPriceWei: BigInt(2_000_000_000),
            expectedGasLimit: BigInt(500_000)
        )
    }

    func testSignerCommitsCalculatorOutputsWhenOracleWinsBothMaxes() throws {
        try assertSignerMatchesCalculator(
            chain: .ethereum,
            quoteGasPrice: "500000000", // 0.5 Gwei, below the oracle
            quoteGas: 210_000,          // below the 900k oracle limit
            maxFeePerGasWei: oneGwei,
            gasLimit: BigInt(900_000),
            expectedGasPriceWei: oneGwei,
            expectedGasLimit: BigInt(900_000)
        )
    }

    func testSignerCommitsCalculatorOutputsForZeroQuoteGasFallback() throws {
        try assertSignerMatchesCalculator(
            chain: .ethereum,
            quoteGasPrice: "1000000000",
            quoteGas: 0, // omitted → 600k default, floored against the 40k limit
            maxFeePerGasWei: oneGwei,
            gasLimit: BigInt(40_000),
            expectedGasPriceWei: oneGwei,
            expectedGasLimit: BigInt(EVMHelper.defaultETHSwapGasUnit)
        )
    }

    func testSignerCommitsCalculatorOutputsForBscLegacySwap() throws {
        // BSC signs legacy (gasPrice) rather than EIP-1559 — the reconciled
        // values feed a different WalletCore txMode but must be the same.
        try assertSignerMatchesCalculator(
            chain: .bscChain,
            quoteGasPrice: "3000000000",
            quoteGas: 250_000,
            maxFeePerGasWei: oneGwei,
            gasLimit: BigInt(600_000),
            expectedGasPriceWei: BigInt(3_000_000_000),
            expectedGasLimit: BigInt(600_000)
        )
    }

    // MARK: - Helpers

    /// Asserts (1) the calculator reconciles to the expected gas parameters and
    /// (2) the signer's pre-image hash equals the hash of the same transaction
    /// priced with those calculator outputs — the byte-level anti-drift pin.
    private func assertSignerMatchesCalculator(
        chain: Chain,
        quoteGasPrice: String,
        quoteGas: Int64,
        maxFeePerGasWei: BigInt,
        gasLimit: BigInt,
        expectedGasPriceWei: BigInt,
        expectedGasLimit: BigInt,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let quote = makeEVMQuote(gasPrice: quoteGasPrice, gas: quoteGas)
        let coin = makeNativeCoin(chain: chain)
        let payload = makeKeysignPayload(
            coin: coin,
            chainSpecific: .Ethereum(
                maxFeePerGasWei: maxFeePerGasWei,
                priorityFeeWei: BigInt(1),
                nonce: 7,
                gasLimit: gasLimit
            ),
            swapPayload: .generic(makeGenericSwapPayload(quote: quote, fromCoin: coin))
        )

        let effective = EVMSwapFee.effective(
            quoteGasPriceWei: EVMSwapFee.quoteGasPriceWei(quote.tx.gasPrice),
            quoteGas: BigInt(quote.tx.gas),
            maxFeePerGasWei: maxFeePerGasWei,
            gasLimit: gasLimit
        )
        XCTAssertEqual(effective.gasPriceWei, expectedGasPriceWei, file: file, line: line)
        XCTAssertEqual(effective.gasLimit, expectedGasLimit, file: file, line: line)

        let signerHashes = try OneInchSwaps().getPreSignedImageHash(
            payload: GenericSwapPayload(
                fromCoin: coin,
                toCoin: makeUSDC(),
                fromAmount: BigInt(1_000_000_000_000_000),
                toAmountDecimal: 1,
                quote: quote,
                provider: .oneInch
            ),
            keysignPayload: payload,
            incrementNonce: false
        )
        let expectedHash = try preImageHash(quote: quote, payload: payload, effective: effective)
        XCTAssertEqual(
            signerHashes,
            [expectedHash],
            "The signer must commit exactly the calculator's gas parameters",
            file: file,
            line: line
        )
    }

    /// Rebuilds the signer's transaction with the calculator's outputs and
    /// returns its pre-image hash.
    private func preImageHash(
        quote: EVMQuote,
        payload: KeysignPayload,
        effective: EVMSwapFee.Effective
    ) throws -> String {
        let input = EthereumSigningInput.with {
            $0.toAddress = quote.tx.to
            $0.transaction = .with {
                $0.contractGeneric = .with {
                    $0.amount = (BigUInt(quote.tx.value) ?? BigUInt.zero).serialize()
                    $0.data = Data(hexString: quote.tx.data.stripHexPrefix()) ?? Data()
                }
            }
        }
        let inputData = try EVMHelper.getHelper(coin: payload.coin).getPreSignedInputData(
            signingInput: input,
            keysignPayload: payload,
            gas: effective.gasLimit.magnitude,
            gasPrice: effective.gasPriceWei.magnitude,
            incrementNonce: false
        )
        let hashes = TransactionCompiler.preImageHashes(coinType: payload.coin.coinType, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        XCTAssertTrue(preSigningOutput.errorMessage.isEmpty, preSigningOutput.errorMessage)
        return preSigningOutput.dataHash.hexString
    }

    // MARK: - Fixtures

    private func makeNativeCoin(chain: Chain) -> Coin {
        let ticker = chain == .bscChain ? "BNB" : "ETH"
        let meta = CoinMeta.make(chain: chain, ticker: ticker, decimals: 18, isNativeToken: true)
        return Coin(asset: meta, address: "0xEe36b9c09FB9c17cCc5a6ac1BD30E152A5faB1c0", hexPublicKey: "")
    }

    private func makeUSDC() -> Coin {
        let meta = CoinMeta.make(chain: .ethereum, ticker: "USDC", decimals: 6, isNativeToken: false)
        return Coin(asset: meta, address: "0xEe36b9c09FB9c17cCc5a6ac1BD30E152A5faB1c0", hexPublicKey: "")
    }

    private func makeEVMQuote(gasPrice: String, gas: Int64) -> EVMQuote {
        EVMQuote(
            dstAmount: "1000000",
            tx: EVMQuote.Transaction(
                from: "0xEe36b9c09FB9c17cCc5a6ac1BD30E152A5faB1c0",
                to: "0x1111111254EEB25477B68fb85Ed929f73A960582",
                data: "0xdeadbeef",
                value: "1000000000000000",
                gasPrice: gasPrice,
                gas: gas
            )
        )
    }

    private func makeGenericSwapPayload(quote: EVMQuote, fromCoin: Coin) -> GenericSwapPayload {
        GenericSwapPayload(
            fromCoin: fromCoin,
            toCoin: makeUSDC(),
            fromAmount: BigInt(1_000_000_000_000_000),
            toAmountDecimal: 1,
            quote: quote,
            provider: .oneInch
        )
    }

    private func makeKeysignPayload(
        coin: Coin,
        chainSpecific: BlockChainSpecific,
        swapPayload: SwapPayload?
    ) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: "0x1111111254EEB25477B68fb85Ed929f73A960582",
            toAmount: BigInt(1_000_000_000_000_000),
            chainSpecific: chainSpecific,
            utxos: [],
            memo: nil,
            swapPayload: swapPayload,
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
}
