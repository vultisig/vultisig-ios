//
//  CosmosGasPricedFeeScalingTests.swift
//  VultisigAppTests
//
//  Regression tests for the Terra Classic / dYdX insufficient-fee bug.
//
//  These chains sign a DYNAMIC `gas_wanted` (the relayed simulated limit) but
//  their fee AMOUNT (`chainSpecific.gas`) is priced for the static per-chain
//  limit and is NOT re-derived by `CosmosFeeFloorConfig.flooredFee` (they are
//  absent from that table). Once the simulated limit exceeds the static one the
//  signed fee undershoots the ante handler's `fee >= gas_wanted × min gas price`
//  check and the tx is rejected on-chain ("insufficient fee", code 13).
//
//  The fix re-derives the fee amount from the same `effectiveGasLimit` that gets
//  signed by scaling the (known-sufficient) static amount by the gas-limit ratio
//  — `ceil(base × effectiveGasLimit / staticGasLimit)` — while preserving any
//  burn tax folded in for Terra Classic. At the static limit the re-derivation
//  returns the static amount verbatim, so the non-simulated path is byte
//  identical, and it is a pure function of the relayed limit + static constants,
//  so co-signers stay byte-parity consistent.
//

@testable import VultisigApp
import WalletCore
import XCTest

final class CosmosGasPricedFeeScalingTests: XCTestCase {

    // MARK: - CosmosGasPricedFee.scaled (pure ceil-scaling math)

    func testScaledUnchangedAtSameLimit() {
        // The non-simulated path (effective == static) must be byte-identical.
        XCTAssertEqual(CosmosGasPricedFee.scaled(base: 8_497_500, fromGasLimit: 300_000, toGasLimit: 300_000), 8_497_500)
    }

    func testScaledDoublesAtDoubleLimit() {
        XCTAssertEqual(CosmosGasPricedFee.scaled(base: 100, fromGasLimit: 300, toGasLimit: 600), 200)
    }

    func testScaledRoundsUpNeverUndershoots() {
        // 10 × 4 / 3 = 13.33… must round UP to 14 so the fee never undershoots
        // the chain's `gas_wanted × price` minimum.
        XCTAssertEqual(CosmosGasPricedFee.scaled(base: 10, fromGasLimit: 3, toGasLimit: 4), 14)
    }

    func testScaledTerraBaseAt30PercentBump() {
        // 8_497_500 (= 300k × 28.325 uluna/gas) scaled to 390k = 300k × 1.3.
        XCTAssertEqual(CosmosGasPricedFee.scaled(base: 8_497_500, fromGasLimit: 300_000, toGasLimit: 390_000), 11_046_750)
    }

    func testScaledZeroFromLimitReturnsBase() {
        XCTAssertEqual(CosmosGasPricedFee.scaled(base: 100, fromGasLimit: 0, toGasLimit: 500), 100)
    }

    // MARK: - TerraClassicTax.scaledSendFee (base scales, folded burn tax preserved)

    func testTerraScaledFeeStaticLimitIsByteIdentical() {
        // At the static 300k limit the re-derived amount MUST equal the upstream
        // static value exactly (base + folded tax), for every token class.
        let luncStatic = TerraClassicTax.ulunaBaseGas + 5_000 // base + burn tax
        XCTAssertEqual(
            TerraClassicTax.scaledSendFee(staticFee: luncStatic, contractAddress: "", isNativeToken: true, gasLimit: 300_000),
            luncStatic
        )
        let ustcStatic = TerraClassicTax.uusdBaseGas + 3_000
        XCTAssertEqual(
            TerraClassicTax.scaledSendFee(staticFee: ustcStatic, contractAddress: "uusd", isNativeToken: false, gasLimit: 300_000),
            ustcStatic
        )
    }

    func testTerraNativeScaledFeeScalesBaseKeepsTax() {
        // LUNC: base 8_497_500 + burn tax 5_000. Scaling to 390k must scale ONLY
        // the base (28.325/gas) and carry the tax through unchanged.
        let tax: UInt64 = 5_000
        let staticFee = TerraClassicTax.ulunaBaseGas + tax
        let fee = TerraClassicTax.scaledSendFee(staticFee: staticFee, contractAddress: "", isNativeToken: true, gasLimit: 390_000)
        XCTAssertEqual(fee, 11_046_750 + tax)
        // Satisfies the chain's `fee >= gas_wanted × price + tax` check…
        XCTAssertGreaterThanOrEqual(fee, 11_046_750 + tax)
        // …which the OLD static amount did NOT (this is the bug).
        XCTAssertLessThan(staticFee, 11_046_750 + tax)
    }

    func testTerraBankDenomScaledFeeUsesUusdBase() {
        // USTC (uusd) is priced at the uusd base (0.75/gas), NOT the uluna base.
        let tax: UInt64 = 3_000
        let staticFee = TerraClassicTax.uusdBaseGas + tax // 225_000 + 3_000
        let fee = TerraClassicTax.scaledSendFee(staticFee: staticFee, contractAddress: "uusd", isNativeToken: false, gasLimit: 360_000)
        // 225_000 × 360k/300k = 270_000, + 3_000 tax.
        XCTAssertEqual(fee, 270_000 + tax)
    }

    func testTerraCW20ScaledFeeHasNoTax() {
        // CW20 (terra1…) pays its fee in uluna with no folded tax, so the whole
        // amount scales.
        let cw20 = "terra1nsuqsk6kh58ulczatwev87ttq2z6r3pusulg9r24mfj2fvtzd4uq3exn26"
        let fee = TerraClassicTax.scaledSendFee(staticFee: TerraClassicTax.ulunaBaseGas, contractAddress: cw20, isNativeToken: false, gasLimit: 390_000)
        XCTAssertEqual(fee, 11_046_750)
    }

    // MARK: - Terra Classic signing input (end-to-end via TerraHelperStruct)

    private func luncCoin() -> Coin {
        let meta = CoinMeta(
            chain: .terraClassic,
            ticker: "LUNC",
            logo: "lunc",
            decimals: 6,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: true
        )
        let hexPublicKey = "02" + String(repeating: "0", count: 64)
        return Coin(asset: meta, address: "terra1from", hexPublicKey: hexPublicKey)
    }

    private func terraPayload(coin: Coin, gas: UInt64, gasLimit: UInt64?) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: "terra1to",
            toAmount: 1_000_000,
            chainSpecific: .Cosmos(
                accountNumber: 7,
                sequence: 3,
                gas: gas,
                transactionType: 0,
                ibcDenomTrace: nil,
                gasLimit: gasLimit
            ),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "",
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

    private func terraFee(coin: Coin, gas: UInt64, gasLimit: UInt64?) throws -> WalletCore.CosmosFee {
        let inputData = try TerraHelperStruct.getPreSignedInputData(keysignPayload: terraPayload(coin: coin, gas: gas, gasLimit: gasLimit), chain: .terraClassic)
        return try CosmosSigningInput(serializedBytes: inputData).fee
    }

    func testTerraClassicSimulatedLimitScalesSignedFeeAmount() throws {
        // A simulated relayed limit above 300k: the signed gas_wanted rises to
        // 390k and the fee amount must scale with it (base 28.325/gas + tax),
        // instead of staying at the short static value that caused code 13.
        let tax: UInt64 = 5_000
        let staticGas = TerraClassicTax.ulunaBaseGas + tax
        let fee = try terraFee(coin: luncCoin(), gas: staticGas, gasLimit: 390_000)

        XCTAssertEqual(fee.gas, 390_000, "signed gas_wanted must be the relayed limit")
        let amount = UInt64(fee.amounts.first?.amount ?? "0") ?? 0
        XCTAssertEqual(amount, 11_046_750 + tax, "fee amount must track the signed gas_wanted")
        XCTAssertGreaterThanOrEqual(amount, fee.gas * 28_325 / 1_000 + tax,
                                    "fee must satisfy gas_wanted × 28.325 uluna/gas + tax")
        XCTAssertEqual(fee.amounts.first?.denom, "uluna")
    }

    func testTerraClassicNoRelayedLimitIsByteIdentical() throws {
        // relayedGasLimit == nil → effective == 300k → the built fee is exactly
        // the pre-fix static value, and the whole SignDoc input is identical to
        // the explicit-300k build (the non-simulated path is byte-unchanged).
        let staticGas = TerraClassicTax.ulunaBaseGas + 5_000
        let coin = luncCoin()

        let nilFee = try terraFee(coin: coin, gas: staticGas, gasLimit: nil)
        XCTAssertEqual(nilFee.gas, TerraHelperStruct.GasLimit)
        XCTAssertEqual(UInt64(nilFee.amounts.first?.amount ?? "0"), staticGas,
                       "absent relayed limit must reproduce the static fee amount exactly")

        let nilInput = try TerraHelperStruct.getPreSignedInputData(keysignPayload: terraPayload(coin: coin, gas: staticGas, gasLimit: nil), chain: .terraClassic)
        let staticInput = try TerraHelperStruct.getPreSignedInputData(keysignPayload: terraPayload(coin: coin, gas: staticGas, gasLimit: TerraHelperStruct.GasLimit), chain: .terraClassic)
        XCTAssertEqual(nilInput, staticInput, "nil and explicit static limit must yield byte-identical SignDoc input")
    }

    func testTerraClassicBankDenomScalesSignedFeeAmount() throws {
        // USTC (uusd bank denom): fee is denominated in uusd and scales off the
        // uusd base, preserving the folded burn tax.
        let meta = CoinMeta(chain: .terraClassic, ticker: "USTC", logo: "ustc", decimals: 6, priceProviderId: "", contractAddress: "uusd", isNativeToken: false)
        let coin = Coin(asset: meta, address: "terra1from", hexPublicKey: "02" + String(repeating: "0", count: 64))
        let tax: UInt64 = 3_000
        let staticGas = TerraClassicTax.uusdBaseGas + tax

        let fee = try terraFee(coin: coin, gas: staticGas, gasLimit: 360_000)
        XCTAssertEqual(fee.gas, 360_000)
        XCTAssertEqual(UInt64(fee.amounts.first?.amount ?? "0"), 270_000 + tax)
        XCTAssertEqual(fee.amounts.first?.denom, "uusd")

        // Non-simulated path unchanged.
        let nilFee = try terraFee(coin: coin, gas: staticGas, gasLimit: nil)
        XCTAssertEqual(UInt64(nilFee.amounts.first?.amount ?? "0"), staticGas)
    }

    func testPlainTerraFeeAmountStaysFlatRegardlessOfRelayedLimit() throws {
        // Plain Terra (phoenix-1) pays a FLAT fee, not `gasLimit × price`, so a
        // relayed limit must move the signed gas_wanted but NOT the fee amount.
        // TerraHelperStruct serves both Terra and Terra Classic; only Terra
        // Classic re-derives. (Guards the `.terraClassic` gate and mirrors the
        // pinned ChainHelperTests Terra hashes.)
        let meta = CoinMeta(chain: .terra, ticker: "LUNA", logo: "luna", decimals: 6, priceProviderId: "", contractAddress: "", isNativeToken: true)
        let coin = Coin(asset: meta, address: "terra1from", hexPublicKey: "02" + String(repeating: "0", count: 64))
        let gas: UInt64 = 7_500
        let inputData = try TerraHelperStruct.getPreSignedInputData(keysignPayload: terraPayload(coin: coin, gas: gas, gasLimit: 390_000), chain: .terra)
        let fee = try CosmosSigningInput(serializedBytes: inputData).fee
        XCTAssertEqual(fee.gas, 390_000, "plain Terra still honors the relayed gas_wanted")
        XCTAssertEqual(UInt64(fee.amounts.first?.amount ?? "0"), gas, "plain Terra fee amount must stay flat (not re-derived)")
    }

    func testTerraClassicSameRelayedLimitIsDeterministic() throws {
        // Byte-parity: two independent builds with the same relayed limit must
        // produce identical SignDoc input (no per-device / simulation-time state).
        let staticGas = TerraClassicTax.ulunaBaseGas + 5_000
        let coin = luncCoin()
        let a = try TerraHelperStruct.getPreSignedInputData(keysignPayload: terraPayload(coin: coin, gas: staticGas, gasLimit: 390_000), chain: .terraClassic)
        let b = try TerraHelperStruct.getPreSignedInputData(keysignPayload: terraPayload(coin: coin, gas: staticGas, gasLimit: 390_000), chain: .terraClassic)
        XCTAssertEqual(a, b, "same relayed limit must yield byte-identical input on every co-signer")

        let different = try TerraHelperStruct.getPreSignedInputData(keysignPayload: terraPayload(coin: coin, gas: staticGas, gasLimit: 300_000), chain: .terraClassic)
        XCTAssertNotEqual(a, different, "a different relayed limit must change the signed bytes")
    }

    // MARK: - dYdX signing input (same decoupling, no tax)

    private func dydxCoinAndAddress() throws -> (Coin, String) {
        // Derive a valid dydx1… address (DydxHelperStruct validates the toAddress
        // via AnyAddress) and a matching pubkey.
        let priv = try XCTUnwrap(PrivateKey(data: Data(repeating: 1, count: 32)))
        let pub = priv.getPublicKeySecp256k1(compressed: true)
        let address = AnyAddress(publicKey: pub, coin: .dydx).description
        let meta = CoinMeta(chain: .dydx, ticker: "DYDX", logo: "dydx", decimals: 18, priceProviderId: "", contractAddress: "", isNativeToken: true)
        return (Coin(asset: meta, address: address, hexPublicKey: pub.data.hexString), address)
    }

    private func dydxPayload(coin: Coin, toAddress: String, gas: UInt64, gasLimit: UInt64?) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: toAddress,
            toAmount: 1_000_000,
            chainSpecific: .Cosmos(
                accountNumber: 7,
                sequence: 3,
                gas: gas,
                transactionType: 0,
                ibcDenomTrace: nil,
                gasLimit: gasLimit
            ),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "",
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

    func testDydxSimulatedLimitScalesSignedFeeAmount() throws {
        // dYdX's flat fee (2.5e15 adydx) == 200k × 12.5e9 min gas price, so it has
        // zero gas-portion headroom: a relayed limit above 200k must scale the
        // amount, or the signed fee undershoots dYdX's ante check.
        let (coin, address) = try dydxCoinAndAddress()
        let staticGas = DydxHelperStruct.DydxGasLimit // 2_500_000_000_000_000
        let inputData = try DydxHelperStruct.getPreSignedInputData(keysignPayload: dydxPayload(coin: coin, toAddress: address, gas: staticGas, gasLimit: 260_000))
        let fee = try CosmosSigningInput(serializedBytes: inputData).fee

        XCTAssertEqual(fee.gas, 260_000)
        XCTAssertEqual(UInt64(fee.amounts.first?.amount ?? "0"), 3_250_000_000_000_000,
                       "fee amount must scale to 200k→260k (× 1.3)")
        XCTAssertLessThan(staticGas, 3_250_000_000_000_000, "the old static amount was short (the bug)")
    }

    func testDydxNoRelayedLimitIsByteIdentical() throws {
        let (coin, address) = try dydxCoinAndAddress()
        let staticGas = DydxHelperStruct.DydxGasLimit
        let nilInput = try DydxHelperStruct.getPreSignedInputData(keysignPayload: dydxPayload(coin: coin, toAddress: address, gas: staticGas, gasLimit: nil))
        let staticInput = try DydxHelperStruct.getPreSignedInputData(keysignPayload: dydxPayload(coin: coin, toAddress: address, gas: staticGas, gasLimit: DydxHelperStruct.staticGasLimit))
        XCTAssertEqual(nilInput, staticInput, "nil and explicit static limit must be byte-identical")

        let fee = try CosmosSigningInput(serializedBytes: nilInput).fee
        XCTAssertEqual(fee.gas, DydxHelperStruct.staticGasLimit)
        XCTAssertEqual(UInt64(fee.amounts.first?.amount ?? "0"), staticGas,
                       "absent relayed limit must reproduce the static fee amount exactly")
    }
}
