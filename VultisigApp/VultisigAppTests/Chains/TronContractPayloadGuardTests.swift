//
//  TronContractPayloadGuardTests.swift
//  VultisigAppTests
//
//  A dApp keysign payload carries a typed TRON contract that `TronHelper`
//  signs verbatim, while Verify shows the top-level coin / toAddress /
//  toAmount. These tests build real payloads through the signing entry point
//  and assert that anything whose display fields disagree with the signed
//  contract is refused before any signing input exists.
//

import BigInt
import WalletCore
import XCTest
@testable import VultisigApp

final class TronContractPayloadGuardTests: XCTestCase {

    private let witness = "41e0e0f1a3a3f3e2d1c0b0a0908070605040302010"
    private let hash32 = "e63d3f0f2a3a3f3e2d1c0b0a09080706050403020100ffeeddccbbaa99887766"
    private let usdtContract = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
    private let otherTokenContract = "TXLAQ63Xg1NAzckPwKHvzw7CSEmLMEqcdj"

    private lazy var trx = SigningGoldenFactory.coin(chain: .tron, ticker: "TRX", decimals: 6, curve: .secp256k1, uncompressedSecp: true)
    private lazy var usdt = makeToken(contractAddress: usdtContract)
    private lazy var recipient = SigningGoldenFactory.recipient(.tron)
    private lazy var attacker = Self.address(forKeyByte: 0x43)

    // MARK: - TransferContract

    func testMatchingTrxTransferIsSignedAsDeclared() throws {
        let payload = makePayload(coin: trx, toAddress: recipient, toAmount: 1_000_000, transfer: transfer(to: recipient, amount: "1000000"))

        let input = try signingInput(payload)

        guard case .transfer(let contract) = input.transaction.contractOneof else {
            return XCTFail("expected transfer contract")
        }
        XCTAssertEqual(contract.ownerAddress, trx.address)
        XCTAssertEqual(contract.toAddress, recipient)
        XCTAssertEqual(contract.amount, 1_000_000)
    }

    func testTrxTransferWithDifferentRecipientIsRefused() {
        let payload = makePayload(coin: trx, toAddress: recipient, toAmount: 1_000_000, transfer: transfer(to: attacker, amount: "1000000"))

        assertRefused(payload)
    }

    func testTrxTransferWithDifferentAmountIsRefused() {
        let payload = makePayload(coin: trx, toAddress: recipient, toAmount: 1_000_000, transfer: transfer(to: recipient, amount: "9000000"))

        assertRefused(payload)
    }

    func testTrxTransferWithForeignOwnerIsRefused() {
        let payload = makePayload(coin: trx, toAddress: recipient, toAmount: 1, transfer: transfer(owner: attacker, to: recipient, amount: "1"))

        assertRefused(payload)
    }

    func testTrxTransferShownAsTokenIsRefused() {
        let payload = makePayload(coin: usdt, toAddress: recipient, toAmount: 1_000_000, transfer: transfer(to: recipient, amount: "1000000"))

        assertRefused(payload)
    }

    func testTransferAmountBeyondInt64IsRefused() {
        let tooBig = "9223372036854775808"
        let payload = makePayload(coin: trx, toAddress: recipient, toAmount: BigInt(tooBig)!, transfer: transfer(to: recipient, amount: tooBig))

        assertRefused(payload)
    }

    func testTransferRecipientInHexMatchesBase58Display() throws {
        let payload = makePayload(coin: trx, toAddress: recipient, toAmount: 5, transfer: transfer(to: Self.hex(of: recipient), amount: "5"))

        XCTAssertNoThrow(try TronContractPayloadGuard.check(payload, contract: payload.tronTransferContractPayload!))
    }

    // MARK: - TransferAssetContract

    func testMatchingAssetTransferIsAccepted() throws {
        let asset = TronTransferAssetContractPayload(toAddress: recipient, ownerAddress: trx.address, amount: "7", assetName: "1002000")
        let payload = makePayload(coin: usdt, toAddress: recipient, toAmount: 7, asset: asset)

        let input = try signingInput(payload)

        guard case .transferAsset(let contract) = input.transaction.contractOneof else {
            return XCTFail("expected transferAsset contract")
        }
        XCTAssertEqual(contract.amount, 7)
        XCTAssertEqual(contract.toAddress, recipient)
    }

    func testAssetTransferMismatchesAreRefused() {
        let wrongRecipient = TronTransferAssetContractPayload(toAddress: attacker, ownerAddress: trx.address, amount: "7", assetName: "1002000")
        let wrongAmount = TronTransferAssetContractPayload(toAddress: recipient, ownerAddress: trx.address, amount: "70", assetName: "1002000")
        let wrongOwner = TronTransferAssetContractPayload(toAddress: recipient, ownerAddress: attacker, amount: "7", assetName: "1002000")

        for asset in [wrongRecipient, wrongAmount, wrongOwner] {
            assertRefused(makePayload(coin: usdt, toAddress: recipient, toAmount: 7, asset: asset))
        }
    }

    func testAssetTransferShownAsTrxIsRefused() {
        let asset = TronTransferAssetContractPayload(toAddress: recipient, ownerAddress: trx.address, amount: "7", assetName: "1002000")

        assertRefused(makePayload(coin: trx, toAddress: recipient, toAmount: 7, asset: asset))
    }

    // MARK: - TriggerSmartContract: TRC-20 transfer

    func testMatchingTrc20TransferIsSignedFromTheDecodedData() throws {
        let data = Self.trc20Transfer(to: recipient, amount: 2_500_000)
        let payload = makePayload(coin: usdt, toAddress: recipient, toAmount: 2_500_000, trigger: trigger(contract: usdtContract, data: data))

        let input = try signingInput(payload)

        guard case .triggerSmartContract(let contract) = input.transaction.contractOneof else {
            return XCTFail("expected triggerSmartContract")
        }
        XCTAssertEqual(contract.data.hexString, String(data.dropFirst(2)))
        XCTAssertEqual(contract.contractAddress, usdtContract)
    }

    func testTrc20TransferWithHexDisplayedRecipientIsAccepted() throws {
        let data = Self.trc20Transfer(to: recipient, amount: 10)
        let payload = makePayload(coin: usdt, toAddress: Self.hex(of: recipient), toAmount: 10, trigger: trigger(contract: usdtContract, data: data))

        XCTAssertNoThrow(try signingInput(payload))
    }

    func testTrc20TransferWithContractInHexIsAccepted() throws {
        let data = Self.trc20Transfer(to: recipient, amount: 10)
        let payload = makePayload(coin: usdt, toAddress: recipient, toAmount: 10, trigger: trigger(contract: Self.hex(of: usdtContract), data: data))

        XCTAssertNoThrow(try TronContractPayloadGuard.check(payload, contract: payload.tronTriggerSmartContractPayload!))
    }

    func testTrc20TransferToDifferentRecipientThanDisplayedIsRefused() {
        let data = Self.trc20Transfer(to: attacker, amount: 10)
        let payload = makePayload(coin: usdt, toAddress: recipient, toAmount: 10, trigger: trigger(contract: usdtContract, data: data))

        assertRefused(payload)
    }

    func testTrc20TransferOfDifferentAmountThanDisplayedIsRefused() {
        let data = Self.trc20Transfer(to: recipient, amount: 10_000_000)
        let payload = makePayload(coin: usdt, toAddress: recipient, toAmount: 10, trigger: trigger(contract: usdtContract, data: data))

        assertRefused(payload)
    }

    func testTrc20TransferWithAttachedTrxIsRefused() {
        let data = Self.trc20Transfer(to: recipient, amount: 10)
        let payload = makePayload(coin: usdt, toAddress: recipient, toAmount: 10, trigger: trigger(contract: usdtContract, data: data, callValue: "5000000"))

        assertRefused(payload)
    }

    func testTrc20TransferShownAsTrxIsRefused() {
        let data = Self.trc20Transfer(to: recipient, amount: 10)
        let payload = makePayload(coin: trx, toAddress: recipient, toAmount: 10, trigger: trigger(contract: usdtContract, data: data))

        assertRefused(payload)
    }

    func testTrc20TransferShownAsADifferentTokenIsRefused() {
        let data = Self.trc20Transfer(to: recipient, amount: 10)
        let payload = makePayload(coin: makeToken(contractAddress: otherTokenContract), toAddress: recipient, toAmount: 10, trigger: trigger(contract: usdtContract, data: data))

        assertRefused(payload)
    }

    func testTrc20TransferWithAttachedTrc10TokensIsRefused() {
        let data = Self.trc20Transfer(to: recipient, amount: 10)
        let payload = makePayload(coin: usdt, toAddress: recipient, toAmount: 10, trigger: trigger(contract: usdtContract, data: data, callTokenValue: "1"))

        assertRefused(payload)
    }

    func testTrc20TransferWithForeignOwnerIsRefused() {
        let data = Self.trc20Transfer(to: recipient, amount: 10)
        let payload = makePayload(coin: usdt, toAddress: recipient, toAmount: 10, trigger: trigger(owner: attacker, contract: usdtContract, data: data))

        assertRefused(payload)
    }

    // MARK: - TriggerSmartContract: everything else

    func testMaliciousApproveDisguisedAsTrxSendIsRefused() {
        let maxUint = String(repeating: "f", count: 64)
        let approve = "0x095ea7b3" + Self.word(of: attacker) + maxUint
        let payload = makePayload(coin: trx, toAddress: recipient, toAmount: 1_000_000, trigger: trigger(contract: usdtContract, data: approve))

        assertRefused(payload)
    }

    func testApproveDisplayedAsACallToTheContractIsAccepted() throws {
        let maxUint = String(repeating: "f", count: 64)
        let approve = "0x095ea7b3" + Self.word(of: attacker) + maxUint
        let payload = makePayload(coin: trx, toAddress: usdtContract, toAmount: 0, trigger: trigger(contract: usdtContract, data: approve))

        let input = try signingInput(payload)

        guard case .triggerSmartContract(let contract) = input.transaction.contractOneof else {
            return XCTFail("expected triggerSmartContract")
        }
        XCTAssertEqual(contract.data.hexString, String(approve.dropFirst(2)))
    }

    func testTransferFromIsNotTreatedAsTransfer() {
        let transferFrom = "0x23b872dd" + Self.word(of: attacker) + Self.word(of: recipient) + Self.amountWord(5)
        let payload = makePayload(coin: usdt, toAddress: recipient, toAmount: 5, trigger: trigger(contract: usdtContract, data: transferFrom))

        assertRefused(payload)
    }

    func testContractCallWithTrxValueMustMatchDisplayedAmount() throws {
        let call = trigger(contract: usdtContract, data: "0xd0e30db0", callValue: "3000000")

        XCTAssertNoThrow(try signingInput(makePayload(coin: trx, toAddress: usdtContract, toAmount: 3_000_000, trigger: call)))
        assertRefused(makePayload(coin: trx, toAddress: usdtContract, toAmount: 0, trigger: call))
        assertRefused(makePayload(coin: usdt, toAddress: usdtContract, toAmount: 3_000_000, trigger: call))
    }

    func testContractCallWithAttachedTrc10TokensIsRefused() {
        let call = trigger(contract: usdtContract, data: "0xd0e30db0", callTokenValue: "1")

        assertRefused(makePayload(coin: trx, toAddress: usdtContract, toAmount: 0, trigger: call))
    }

    func testUnparseableCallValueIsRefused() {
        let call = trigger(contract: usdtContract, data: "0xd0e30db0", callValue: "1e6")

        assertRefused(makePayload(coin: trx, toAddress: usdtContract, toAmount: 0, trigger: call))
    }

    func testTruncatedTransferDataFallsBackToTheContractCallRule() {
        let truncated = "0xa9059cbb" + Self.word(of: attacker)
        let payload = makePayload(coin: usdt, toAddress: recipient, toAmount: 0, trigger: trigger(contract: usdtContract, data: truncated))

        assertRefused(payload)
    }

    func testTransferCalldataWithTrailingBytesIsNotTreatedAsTransfer() {
        let data = Self.trc20Transfer(to: recipient, amount: 10) + "deadbeef"
        let payload = makePayload(coin: usdt, toAddress: recipient, toAmount: 10, trigger: trigger(contract: usdtContract, data: data))

        assertRefused(payload)
    }

    func testTransferCalldataWithDirtyAddressPadIsNotTreatedAsTransfer() {
        let dirty = "0xa9059cbb" + "ff" + Self.word(of: recipient).dropFirst(2) + Self.amountWord(10)
        let payload = makePayload(coin: usdt, toAddress: recipient, toAmount: 10, trigger: trigger(contract: usdtContract, data: dirty))

        assertRefused(payload)
    }

    func testRefusalAlsoBlocksPreSignedImageHash() {
        let data = Self.trc20Transfer(to: attacker, amount: 10)
        let payload = makePayload(coin: usdt, toAddress: recipient, toAmount: 10, trigger: trigger(contract: usdtContract, data: data))

        XCTAssertThrowsError(try TronHelper.getPreSignedImageHash(keysignPayload: payload))
    }

    // MARK: - Verify decoding input

    func testVerifyDecodesTheSignedCalldataNotTheMemo() throws {
        let maxUint = String(repeating: "f", count: 64)
        let approve = "0x095ea7b3" + Self.word(of: attacker) + maxUint
        let payload = makePayload(coin: trx, toAddress: usdtContract, toAmount: 0, trigger: trigger(contract: usdtContract, data: approve))
        let input = try signingInput(payload)
        guard case .triggerSmartContract(let contract) = input.transaction.contractOneof else {
            return XCTFail("expected triggerSmartContract")
        }

        let shown = try XCTUnwrap(TronContractPayloadGuard.calldataHex(from: payload.tronTriggerSmartContractPayload?.data))

        XCTAssertEqual(shown, "0x" + contract.data.hexString, "Verify must decode exactly the bytes that are signed")
        XCTAssertEqual(String(shown.prefix(10)), "0x095ea7b3")
    }

    func testCalldataHexIsNilWithoutData() {
        XCTAssertNil(TronContractPayloadGuard.calldataHex(from: nil))
        XCTAssertNil(TronContractPayloadGuard.calldataHex(from: ""))
    }

    func testUnlimitedApproveOnATronContractIsFlaggedByTheExtractor() throws {
        let args = "[\"0x\(Self.word(of: attacker).suffix(40))\",\"\(ContractCallExtractor.maxUInt256Decimal)\"]"

        let pair = try XCTUnwrap(ContractCallExtractor.extract(signature: "approve(address,uint256)", argsJson: args, toAddress: usdtContract))

        XCTAssertEqual(pair.tokenAddress, usdtContract)
        XCTAssertEqual(pair.rawAmount, ContractCallExtractor.maxUInt256Decimal)
        XCTAssertNotNil(ContractCallExtractor.sentinelLabelFor(funcName: "approve"))
    }

    // MARK: - Helpers

    private func signingInput(_ payload: KeysignPayload) throws -> TronSigningInput {
        try TronSigningInput(serializedBytes: TronHelper.getPreSignedInputData(keysignPayload: payload))
    }

    private func assertRefused(_ payload: KeysignPayload, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try TronHelper.getPreSignedInputData(keysignPayload: payload), file: file, line: line) { error in
            XCTAssertTrue("\(error)".contains("TRON contract payload rejected"), "unexpected error: \(error)", file: file, line: line)
        }
    }

    private func transfer(owner: String? = nil, to: String, amount: String) -> TronTransferContractPayload {
        TronTransferContractPayload(toAddress: to, ownerAddress: owner ?? trx.address, amount: amount)
    }

    private func trigger(owner: String? = nil, contract: String, data: String, callValue: String? = nil, callTokenValue: String? = nil) -> TronTriggerSmartContractPayload {
        TronTriggerSmartContractPayload(
            ownerAddress: owner ?? trx.address,
            contractAddress: contract,
            callValue: callValue,
            callTokenValue: callTokenValue,
            tokenId: nil,
            data: data
        )
    }

    private func makeToken(contractAddress: String) -> Coin {
        SigningGoldenFactory.coin(
            chain: .tron, ticker: "USDT", decimals: 6, contractAddress: contractAddress,
            isNativeToken: false, curve: .secp256k1, uncompressedSecp: true
        )
    }

    private func makePayload(
        coin: Coin,
        toAddress: String,
        toAmount: BigInt,
        transfer: TronTransferContractPayload? = nil,
        trigger: TronTriggerSmartContractPayload? = nil,
        asset: TronTransferAssetContractPayload? = nil
    ) -> KeysignPayload {
        SigningGoldenFactory.payload(
            coin: coin,
            toAddress: toAddress,
            toAmount: toAmount,
            chainSpecific: .Tron(
                timestamp: 1_700_000_000_000,
                expiration: 1_700_000_060_000,
                blockHeaderTimestamp: 1_700_000_000_000,
                blockHeaderNumber: 50_000_000,
                blockHeaderVersion: 30,
                blockHeaderTxTrieRoot: hash32,
                blockHeaderParentHash: hash32,
                blockHeaderWitnessAddress: witness,
                gasFeeEstimation: 1_000_000
            ),
            tronTransferContractPayload: transfer,
            tronTriggerSmartContractPayload: trigger,
            tronTransferAssetContractPayload: asset
        )
    }

    private static func address(forKeyByte byte: UInt8) -> String {
        guard let key = PrivateKey(data: Data(repeating: byte, count: 32)) else {
            fatalError("invalid fixture key")
        }
        return CoinType.tron.deriveAddress(privateKey: key)
    }

    /// 41-prefixed hex form of a Base58Check TRON address.
    private static func hex(of base58: String) -> String {
        guard let bytes = Base58.decode(string: base58) else { fatalError("invalid fixture address") }
        return bytes.hexString
    }

    /// ABI word: the 20-byte account left-padded to 32 bytes.
    private static func word(of base58: String) -> String {
        String(repeating: "0", count: 24) + hex(of: base58).dropFirst(2)
    }

    private static func amountWord(_ amount: BigUInt) -> String {
        let hex = String(amount, radix: 16)
        return String(repeating: "0", count: 64 - hex.count) + hex
    }

    private static func trc20Transfer(to base58: String, amount: BigUInt) -> String {
        "0xa9059cbb" + word(of: base58) + amountWord(amount)
    }
}
