//
//  EvmMaxSendClampTests.swift
//  VultisigAppTests
//
//  A native EVM MAX send is `balance − fee`, but the fee it is derived from on
//  the Verify screen and the fee the keysign payload is built from are two
//  independent readings of the same fee market. These cover the arithmetic that
//  re-fits the value to the fee that actually gets signed, plus the OP-stack L1
//  data fee the chain adds to its own balance check on top of the gas term.
//

import BigInt
import CryptoSwift
import XCTest
@testable import VultisigApp

@MainActor
final class EvmMaxSendClampTests: XCTestCase {

    // MARK: - evmMaxSendAmountRaw

    func testClampsDownToTheSignedFeeWhenTheFeeGrew() {
        // 1 ETH balance, quoted at 0.01 ETH, signed at 0.02 ETH.
        let eth = makeCoin(.ethereum, rawBalance: "1000000000000000000")
        let quotedFee = BigInt(stringLiteral: "10000000000000000")
        let signedFee = BigInt(stringLiteral: "20000000000000000")

        let amount = SendCryptoLogic.evmMaxSendAmountRaw(
            coin: eth,
            displayedAmountRaw: balance(eth) - quotedFee,
            signedFee: signedFee,
            extraReserve: .zero
        )

        XCTAssertEqual(amount, balance(eth) - signedFee)
        XCTAssertEqual(amount + signedFee, balance(eth), "the signed value must exactly fill the balance under the signed fee")
    }

    func testNeverRaisesTheAmountWhenTheFeeFell() {
        // Clamping UP would sign more than the Verify screen displayed.
        let eth = makeCoin(.ethereum, rawBalance: "1000000000000000000")
        let quotedFee = BigInt(stringLiteral: "20000000000000000")
        let signedFee = BigInt(stringLiteral: "10000000000000000")
        let displayed = balance(eth) - quotedFee

        let amount = SendCryptoLogic.evmMaxSendAmountRaw(
            coin: eth,
            displayedAmountRaw: displayed,
            signedFee: signedFee,
            extraReserve: .zero
        )

        XCTAssertEqual(amount, displayed)
    }

    func testLeavesTheAmountAloneWhenTheFeeDidNotMove() {
        let eth = makeCoin(.ethereum, rawBalance: "1000000000000000000")
        let fee = BigInt(stringLiteral: "10000000000000000")
        let displayed = balance(eth) - fee

        let amount = SendCryptoLogic.evmMaxSendAmountRaw(
            coin: eth,
            displayedAmountRaw: displayed,
            signedFee: fee,
            extraReserve: .zero
        )

        XCTAssertEqual(amount, displayed)
    }

    func testSubtractsTheOpStackL1DataFeeReserve() {
        let opEth = makeCoin(.optimism, rawBalance: "1000000000000000000")
        let signedFee = BigInt(stringLiteral: "10000000000000000")
        let l1Reserve = BigInt(4_293_564_911) // measured OP mainnet L1 fee scale

        let amount = SendCryptoLogic.evmMaxSendAmountRaw(
            coin: opEth,
            displayedAmountRaw: balance(opEth) - signedFee,
            signedFee: signedFee,
            extraReserve: l1Reserve
        )

        XCTAssertEqual(amount, balance(opEth) - signedFee - l1Reserve)
        XCTAssertEqual(
            amount + signedFee + l1Reserve, balance(opEth),
            "op-geth checks value + gasLimit * maxFeePerGas + l1Cost against the balance"
        )
    }

    func testIsNonPositiveWhenTheSignedFeeExceedsTheBalance() {
        let eth = makeCoin(.ethereum, rawBalance: "1000")
        let amount = SendCryptoLogic.evmMaxSendAmountRaw(
            coin: eth,
            displayedAmountRaw: BigInt(900),
            signedFee: BigInt(5_000),
            extraReserve: .zero
        )
        XCTAssertLessThanOrEqual(amount, .zero, "an unaffordable send must not produce a signable amount")
    }

    /// Reproduces the Arbitrum report verbatim: `have 90995688510130159 want
    /// 90995691390130150`. Arbitrum's native gas-limit floor is 120_000 and its
    /// priority fee is zero, so `maxFeePerGas = baseFee * 1.2`; a 20_000-wei
    /// base-fee tick between the two fetches moves `maxFeePerGas` by 24_000 and
    /// the payload by `120_000 * 24_000 = 2.88e9` — the reported shortfall to
    /// within the 9 wei the two integer truncations cost.
    func testReproducesTheReportedArbitrumShortfallAndFixesIt() {
        let balanceRaw = BigInt(stringLiteral: "90995688510130159")
        let arb = makeCoin(.arbitrum, rawBalance: balanceRaw.description)
        let gasLimit = BigInt(120_000)
        let baseFee1 = BigInt(10_000_000)
        let baseFee2 = baseFee1 + 20_000

        func maxFeePerGas(_ baseFee: BigInt) -> BigInt { (baseFee * 120) / 100 }
        let quotedFee = gasLimit * maxFeePerGas(baseFee1)
        let signedFee = gasLimit * maxFeePerGas(baseFee2)

        // Pre-fix: the amount stays pinned to fee1 while fee2 is signed.
        let unclamped = balanceRaw - quotedFee
        XCTAssertGreaterThan(
            unclamped + signedFee, balanceRaw,
            "the reported failure must reproduce, or this test is not exercising the bug"
        )
        XCTAssertEqual(unclamped + signedFee - balanceRaw, signedFee - quotedFee)
        XCTAssertEqual(signedFee - quotedFee, BigInt(2_880_000_000), "gasLimit * delta(maxFeePerGas) is the reported ~2.88e9 shortfall")

        // Post-fix: the value is re-fitted to the fee the payload carries.
        let clamped = SendCryptoLogic.evmMaxSendAmountRaw(
            coin: arb,
            displayedAmountRaw: unclamped,
            signedFee: signedFee,
            extraReserve: .zero
        )
        XCTAssertEqual(clamped + signedFee, balanceRaw)
    }

    // MARK: - verifyMaxCandidateRaw extra reserve

    func testVerifyMaxCandidateRawDefaultsToNoExtraReserve() {
        let eth = makeCoin(.ethereum, rawBalance: "1000000000000000000")
        let fee = BigInt(stringLiteral: "10000000000000000")
        XCTAssertEqual(
            SendCryptoLogic.verifyMaxCandidateRaw(coin: eth, fee: fee, previousAmountRaw: .zero),
            balance(eth) - fee
        )
    }

    func testVerifyMaxCandidateRawSubtractsTheExtraReserve() {
        let opEth = makeCoin(.optimism, rawBalance: "1000000000000000000")
        let fee = BigInt(stringLiteral: "10000000000000000")
        let reserve = BigInt(4_293_564_911)
        XCTAssertEqual(
            SendCryptoLogic.verifyMaxCandidateRaw(
                coin: opEth,
                fee: fee,
                previousAmountRaw: .zero,
                extraReserve: reserve
            ),
            balance(opEth) - fee - reserve
        )
    }

    // MARK: - amountString

    /// The clamped raw value is written back onto the transaction as a decimal
    /// string, so the rendering itself has to be exact — every wei of the
    /// clamped value present, no scientific notation, no grouping separators.
    func testAmountStringRendersEveryWei() {
        let eth = makeCoin(.ethereum, rawBalance: "0")
        XCTAssertEqual(SendCryptoLogic.amountString(coin: eth, raw: BigInt(1)), "0.000000000000000001")
        XCTAssertEqual(
            SendCryptoLogic.amountString(coin: eth, raw: BigInt(stringLiteral: "12437685400489921")),
            "0.012437685400489921"
        )
        XCTAssertEqual(
            SendCryptoLogic.amountString(coin: eth, raw: BigInt(stringLiteral: "1234567891234567890123")),
            "1234.567891234567890123"
        )

        let usdc = CoinMeta.make(chain: .ethereum, ticker: "USDC", decimals: 6, isNativeToken: false)
        let usdcCoin = Coin(asset: usdc, address: "test-address", hexPublicKey: "")
        XCTAssertEqual(SendCryptoLogic.amountString(coin: usdcCoin, raw: BigInt(200_000_000)), "200")
    }

    /// The signed value is the payload's `BigInt`, never a re-parse of the
    /// rendered string — `String.toDecimal()` goes through `NumberFormatter`
    /// (Double-backed) and cannot carry 18 decimals past ~17 significant
    /// digits. Pinned so the reason the clamp works in raw units, and the
    /// transaction's decimal string only follows it for display, stays on the
    /// record.
    func testAmountInRawReParseIsExactOnlyWithinDoublePrecision() {
        let eth = makeCoin(.ethereum, rawBalance: "0")

        let exact = BigInt(stringLiteral: "12437685400000000")
        XCTAssertEqual(
            SendCryptoLogic.amountInRaw(coin: eth, amount: SendCryptoLogic.amountString(coin: eth, raw: exact)),
            exact
        )

        let beyondDouble = BigInt(stringLiteral: "12437685400489921")
        XCTAssertNotEqual(
            SendCryptoLogic.amountInRaw(coin: eth, amount: SendCryptoLogic.amountString(coin: eth, raw: beyondDouble)),
            beyondDouble,
            "if this starts passing, the amount-string parser gained full precision and the note above is stale"
        )
    }

    // MARK: - Chain.isOpStack

    func testOpStackChainsAreTheOnesExposingTheGasPriceOracle() {
        for chain in [Chain.optimism, .base, .blast, .mantle] {
            XCTAssertTrue(chain.isOpStack, "\(chain.name) is an OP-stack rollup")
        }
        // Probed live against the app's own RPC endpoints: the GasPriceOracle
        // predeploy has no code on any of these, so there is no L1 data fee to
        // reserve.
        for chain in [Chain.ethereum, .arbitrum, .polygon, .avalanche, .bscChain, .zksync, .robinhood] {
            XCTAssertFalse(chain.isOpStack, "\(chain.name) is not an OP-stack rollup")
        }
    }

    // MARK: - GasPriceOracle call encoding

    func testProbePayloadIsDeterministicAndIncompressible() {
        let payload = EvmServiceStruct.l1FeeProbePayload(size: 160)
        XCTAssertEqual(payload.count, 160)
        XCTAssertEqual(payload, EvmServiceStruct.l1FeeProbePayload(size: 160))
        XCTAssertEqual(payload, EvmServiceStruct.l1FeeProbePayload(size: 512).prefix(160),
                       "a longer probe must extend the same stream, not a different one")

        // Fjord prices the FastLZ-compressed size, and FastLZ only shrinks
        // repeated 3-byte windows. Assert there are none, which is what keeps
        // the probe from under-reporting the fee.
        let bytes = [UInt8](payload)
        var windows = Set<[UInt8]>()
        for index in 0...(bytes.count - 3) {
            XCTAssertTrue(windows.insert(Array(bytes[index..<(index + 3)])).inserted, "probe payload repeats a 3-byte window at \(index)")
        }
    }

    /// A counter or stride sequence wraps at 256, and a memo long enough to push
    /// the probe past that made the second block a verbatim copy of the first —
    /// FastLZ compresses that away and the reserve halves. Measured against OP
    /// mainnet at 512 bytes: 4.92e9 for the wrapping payload vs 9.24e9 for
    /// random data. Assert the property FastLZ actually keys on across the whole
    /// probe range, not just a block comparison a shorter cycle could slip past.
    func testProbePayloadHasNoRepeatedWindowAcrossItsWholeRange() {
        let long = [UInt8](EvmServiceStruct.l1FeeProbePayload(size: 2048))
        var windows = Set<[UInt8]>()
        for index in 0...(long.count - 3) {
            XCTAssertTrue(
                windows.insert(Array(long[index..<(index + 3)])).inserted,
                "probe payload repeats a 3-byte window at \(index); FastLZ would compress it away"
            )
        }
    }

    func testProbePayloadHandlesDegenerateSizes() {
        XCTAssertTrue(EvmServiceStruct.l1FeeProbePayload(size: 0).isEmpty)
        XCTAssertTrue(EvmServiceStruct.l1FeeProbePayload(size: -1).isEmpty)
    }

    func testAbiEncodedBytesArgumentMatchesSolidityLayout() {
        let encoded = EvmServiceStruct.abiEncodedBytesArgument(Data([0xde, 0xad, 0xbe, 0xef]))

        let offset = String(encoded.prefix(64))
        let length = String(encoded.dropFirst(64).prefix(64))
        let body = String(encoded.dropFirst(128))

        XCTAssertEqual(offset, String(repeating: "0", count: 62) + "20", "head offset must point one word in")
        XCTAssertEqual(length, String(repeating: "0", count: 63) + "4")
        XCTAssertEqual(body, "deadbeef" + String(repeating: "00", count: 28), "payload must be right-padded to a 32-byte word")
        XCTAssertEqual(encoded.count, 64 + 64 + 64)
    }

    func testAbiEncodedUInt256PadsToOneWord() {
        XCTAssertEqual(EvmServiceStruct.abiEncodedUInt256(.zero), String(repeating: "0", count: 64))
        XCTAssertEqual(EvmServiceStruct.abiEncodedUInt256(BigInt(40_000)), String(repeating: "0", count: 60) + "9c40")
        for value in [BigInt(1), BigInt(120_000), BigInt(stringLiteral: "90995688510130159")] {
            XCTAssertEqual(EvmServiceStruct.abiEncodedUInt256(value).count, 64)
        }
    }

    func testAbiEncodedBytesArgumentPadsToWholeWords() {
        for size in [0, 1, 31, 32, 33, 160] {
            let encoded = EvmServiceStruct.abiEncodedBytesArgument(EvmServiceStruct.l1FeeProbePayload(size: size))
            XCTAssertEqual(encoded.count % 64, 0, "size \(size) produced a non-word-aligned argument")
        }
    }

    /// The selectors are hand-written hex; a typo would make the oracle call
    /// revert, the reserve fail open to zero, and the fix silently regress to
    /// the broadcast rejection it exists to prevent. Derive them from the
    /// signatures instead of trusting the literals.
    func testOracleSelectorsMatchTheirSignatures() {
        func selector(_ signature: String) -> String {
            Data(signature.utf8).sha3(.keccak256).prefix(4)
                .map { String(format: "%02x", $0) }.joined()
        }
        XCTAssertEqual(EvmServiceStruct.getL1FeeSelector, selector("getL1Fee(bytes)"))
        XCTAssertEqual(EvmServiceStruct.getOperatorFeeSelector, selector("getOperatorFee(uint256)"))
        XCTAssertEqual(EvmServiceStruct.gasPriceOracleAddress, "0x420000000000000000000000000000000000000F")
    }

    // MARK: - Reserve aggregation

    func testReserveSumsBothSurcharges() async {
        let sum = await DefaultSendInteractor.opStackReserveSum(
            chain: .optimism,
            l1DataFee: { BigInt(4_293_564_911) },
            operatorFee: { BigInt(400_000_000_000_000) }
        )
        XCTAssertEqual(sum, BigInt(4_293_564_911) + BigInt(400_000_000_000_000))
    }

    /// Blast's oracle predates `getOperatorFee` and reverts on it. That must not
    /// take the L1 data fee down with it — the chain would then reserve nothing
    /// at all, which is the bug.
    func testOperatorFeeFailureLeavesTheL1DataFeeReserved() async {
        let sum = await DefaultSendInteractor.opStackReserveSum(
            chain: .blast,
            l1DataFee: { BigInt(622_082_656) },
            operatorFee: { throw HelperError.runtimeError("execution reverted") }
        )
        XCTAssertEqual(sum, BigInt(622_082_656))
    }

    func testL1DataFeeFailureLeavesTheOperatorFeeReserved() async {
        let sum = await DefaultSendInteractor.opStackReserveSum(
            chain: .mantle,
            l1DataFee: { throw HelperError.runtimeError("transport error") },
            operatorFee: { BigInt(400_000_000_000_000) }
        )
        XCTAssertEqual(sum, BigInt(400_000_000_000_000))
    }

    /// Fail open: an oracle we cannot reach at all leaves the send exactly as it
    /// behaved before these lookups existed, rather than blocking it.
    func testUnreachableOracleReservesNothing() async {
        let sum = await DefaultSendInteractor.opStackReserveSum(
            chain: .optimism,
            l1DataFee: { throw HelperError.runtimeError("transport error") },
            operatorFee: { throw HelperError.runtimeError("transport error") }
        )
        XCTAssertEqual(sum, .zero)
    }

    /// A negative answer is nonsense from a fee oracle, and passing it on would
    /// WIDEN the max amount past what the balance can fund.
    func testNegativeOracleAnswerIsFlooredAtZero() async {
        let sum = await DefaultSendInteractor.opStackReserveSum(
            chain: .optimism,
            l1DataFee: { BigInt(-1_000) },
            operatorFee: { BigInt(500) }
        )
        XCTAssertEqual(sum, BigInt(500))
    }

    // MARK: - Helpers

    private func makeCoin(_ chain: Chain, rawBalance: String) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: "ETH", decimals: 18, isNativeToken: true)
        let coin = Coin(asset: asset, address: "test-address", hexPublicKey: "")
        coin.rawBalance = rawBalance
        return coin
    }

    private func balance(_ coin: Coin) -> BigInt {
        coin.rawBalance.toBigInt(decimals: coin.decimals)
    }
}
