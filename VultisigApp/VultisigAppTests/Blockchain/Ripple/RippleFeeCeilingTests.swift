//
//  RippleFeeCeilingTests.swift
//  VultisigAppTests
//
//  The signed XRP `Fee` is bounded on every signer: the native path (relayed
//  `gas`) and the dApp rawJson path (the JSON's own `Fee`) both refuse a fee
//  above 2 XRP, so a co-signer never signs a fee that burns the account.
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

final class RippleFeeCeilingTests: XCTestCase {

    private static let account = "rPVMhWBsfF9iMXYj3aAzJVkPDTFNSyWdKy"
    private static let destination = "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh"
    private static let publicKeyHex = "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
    private static let ceiling = RippleHelper.maxFeeDrops

    private static func makeCoin() -> Coin {
        let meta = CoinMeta(
            chain: .ripple,
            ticker: "XRP",
            logo: "xrp",
            decimals: 6,
            priceProviderId: "ripple",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: meta, address: account, hexPublicKey: publicKeyHex)
    }

    private static func makePayload(gas: UInt64, memo: String? = nil, rawJson: String? = nil) -> KeysignPayload {
        KeysignPayload(
            coin: makeCoin(),
            toAddress: destination,
            toAmount: BigInt(1_000_000),
            chainSpecific: .Ripple(sequence: 99, gas: gas, lastLedgerSequence: 12_345_678),
            utxos: [],
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "iPhone-test",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: rawJson.map { .signRipple(SignRipple(rawJson: $0)) }
        )
    }

    private static func paymentJson(feeField: String) -> String {
        let fee = feeField.isEmpty ? "" : "\"Fee\":\(feeField),"
        return """
        {"TransactionType":"Payment","Account":"\(account)","Destination":"\(destination)","Amount":"1000000",\(fee)"Sequence":99,"LastLedgerSequence":12345678}
        """
    }

    // MARK: - Native path

    func testNativeFeeAtCeilingIsAccepted() throws {
        let data = try RippleHelper.getPreSignedInputData(keysignPayload: Self.makePayload(gas: Self.ceiling))
        let input = try RippleSigningInput(serializedBytes: data)
        XCTAssertEqual(input.fee, Int64(Self.ceiling))
    }

    func testNativeFeeAboveCeilingIsRefused() {
        XCTAssertThrowsError(
            try RippleHelper.getPreSignedInputData(keysignPayload: Self.makePayload(gas: Self.ceiling + 1))
        )
    }

    func testNativeMemoPathFeeAboveCeilingIsRefused() {
        XCTAssertThrowsError(
            try RippleHelper.getPreSignedInputData(
                keysignPayload: Self.makePayload(gas: Self.ceiling + 1, memo: "=:BTC.BTC:bc1qexample")
            )
        )
    }

    func testNativeFeeNearInt64MaxIsRefused() {
        XCTAssertThrowsError(
            try RippleHelper.getPreSignedInputData(keysignPayload: Self.makePayload(gas: UInt64(Int64.max)))
        )
    }

    // MARK: - dApp rawJson path

    func testDappFeeAtCeilingIsAccepted() throws {
        let json = Self.paymentJson(feeField: "\"\(Self.ceiling)\"")
        XCTAssertNoThrow(
            try RippleHelper.getPreSignedInputData(keysignPayload: Self.makePayload(gas: 10, rawJson: json))
        )
    }

    func testDappNormalFeeIsAccepted() throws {
        let json = Self.paymentJson(feeField: "\"400\"")
        XCTAssertNoThrow(
            try RippleHelper.getPreSignedInputData(keysignPayload: Self.makePayload(gas: 10, rawJson: json))
        )
    }

    func testDappFeeAboveCeilingIsRefused() {
        let json = Self.paymentJson(feeField: "\"\(Self.ceiling + 1)\"")
        XCTAssertThrowsError(
            try RippleHelper.getPreSignedInputData(keysignPayload: Self.makePayload(gas: 10, rawJson: json))
        )
    }

    func testDappFeeBeyondUInt64IsRefused() {
        let json = Self.paymentJson(feeField: "\"99999999999999999999999\"")
        XCTAssertThrowsError(
            try RippleHelper.getPreSignedInputData(keysignPayload: Self.makePayload(gas: 10, rawJson: json))
        )
    }

    func testDappMalformedFeeIsRefused() {
        for bad in ["\"-1\"", "\"0\"", "\"1.5\"", "\"abc\"", "\"\"", "400", "null", "{}", "true"] {
            let json = Self.paymentJson(feeField: bad)
            XCTAssertThrowsError(
                try RippleHelper.getPreSignedInputData(keysignPayload: Self.makePayload(gas: 10, rawJson: json)),
                "Fee \(bad) must be refused"
            )
        }
    }

    func testDappFeeAboveCeilingRefusedForNonPaymentTypes() {
        let json = """
        {"TransactionType":"OfferCreate","Account":"\(Self.account)","TakerGets":"5000000","TakerPays":{"currency":"USD","issuer":"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh","value":"10"},"Fee":"\(Self.ceiling + 1)","Sequence":99,"LastLedgerSequence":12345678}
        """
        XCTAssertThrowsError(
            try RippleHelper.getPreSignedInputData(keysignPayload: Self.makePayload(gas: 10, rawJson: json))
        )
    }

    func testDappRelayedGasAboveCeilingIsRefused() {
        let json = Self.paymentJson(feeField: "\"10\"")
        XCTAssertThrowsError(
            try RippleHelper.getPreSignedInputData(
                keysignPayload: Self.makePayload(gas: Self.ceiling + 1, rawJson: json)
            )
        )
    }
}
