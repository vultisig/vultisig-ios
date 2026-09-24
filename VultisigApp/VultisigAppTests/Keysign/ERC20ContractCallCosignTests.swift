//
//  ERC20ContractCallCosignTests.swift
//  VultisigAppTests
//
//  A token payload whose memo carries `0x` calldata with a zero amount is a
//  contract call (the SDK's VULT stake: `depositFor` on sVULT), optionally
//  preceded by approve legs. Co-signers rebuild every hash from the payload,
//  so iOS has to derive the same list as the SDK initiator.
//
//  The SDK vectors below were generated once with the SDK's own resolver:
//  vultisig-sdk origin/main 30dd259d7, a vitest file calling
//  `buildVultStakeKeysignPayload` (allowance and chain-specific mocked:
//  nonce 12, maxFeePerGas 30 gwei, priority 1 gwei, gasLimit 150000,
//  amount 1.5 VULT, signer key `SigningGoldenSigner.secp256k1KeyHex`) and then
//  `getEncodedSigningInputs` + `getPreSigningHashes`. The payload is the SDK's
//  serialized `KeysignPayload`, so the wire decode is covered too.
//

import BigInt
import VultisigCommonData
import WalletCore
import XCTest
@testable import VultisigApp

final class ERC20ContractCallCosignTests: XCTestCase {

    // MARK: - SDK golden vectors

    func testSdkVultStakeWithApproveSignsApproveThenDepositFor() throws {
        let payload = try sdkPayload(Self.sdkStakeWithApprove)
        XCTAssertEqual(payload.approvePayload, ERC20ApprovePayload(amount: Self.stakeAmount, spender: Self.sVult))

        let messages = try KeysignMessageFactory(payload: payload).getKeysignMessages()

        XCTAssertEqual(messages, [
            "b32122eba723d0708b9d9d3d060221d0358d4d804cd23618fb1d1ebc93e6255f",
            "7990ace733c22100cccd7d3a242159b541e4166884ebe97472b6f903c29272c4"
        ])
    }

    func testSdkVultStakeWithoutApproveSignsOnlyDepositFor() throws {
        let payload = try sdkPayload(Self.sdkStakeWithoutApprove)
        XCTAssertNil(payload.approvePayload)

        let messages = try KeysignMessageFactory(payload: payload).getKeysignMessages()

        XCTAssertEqual(messages, ["5c6fba48875693208e53e74405307a0378d9aa062409c19e1329985d6a3f77f5"])
    }

    func testDepositForIsAContractCallToTheStakingContractAtTheNextNonce() throws {
        let payload = try sdkPayload(Self.sdkStakeWithApprove)

        let input = try EthereumSigningInput(serializedBytes: ERC20Helper(coinType: .ethereum).getPreSignedInputData(
            keysignPayload: payload,
            nonceOffset: payload.approveNonceOffset
        ))

        XCTAssertEqual(BigUInt(input.nonce), 13)
        XCTAssertEqual(input.toAddress, Self.sVult)
        XCTAssertEqual(input.transaction.contractGeneric.data, Data(hexString: try XCTUnwrap(payload.memo).stripHexPrefix()))
        XCTAssertEqual(BigUInt(input.transaction.contractGeneric.amount), 0)
    }

    // MARK: - Reset allowance first (iOS only)

    /// The SDK does not implement the reset yet, so this can't be checked
    /// against it: `approve(0)`@12, `approve(amount)`@13, `depositFor`@14.
    func testResetAllowanceFirstMovesDepositForTwoNoncesOn() throws {
        let payload = try sdkPayload(Self.sdkStakeWithApprove, resetAllowanceFirst: true)
        let approve = try XCTUnwrap(payload.approvePayload)

        let messages = try KeysignMessageFactory(payload: payload).getKeysignMessages()

        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(
            Array(messages.prefix(2)),
            try THORChainSwaps().getPreSignedApproveImageHash(approvePayload: approve, keysignPayload: payload)
        )
        let atFourteen = try sdkPayload(Self.sdkStakeWithoutApprove, nonce: 14)
        XCTAssertEqual(messages.last, try ERC20Helper(coinType: .ethereum).getPreSignedImageHash(keysignPayload: atFourteen).first)
    }

    // MARK: - Signed transaction assembly

    @MainActor
    func testSignedVultStakeCarriesTheApproveThenTheDeposit() throws {
        let payload = try sdkPayload(Self.sdkStakeWithApprove)
        let signatures = try SigningGoldenSigner.signatures(
            forImageHashes: KeysignMessageFactory(payload: payload).getKeysignMessages(),
            curve: .secp256k1
        )
        let viewModel = KeysignViewModel()
        viewModel.signatures = signatures

        let signed = try viewModel.getSignedTransaction(keysignPayload: payload)

        guard case .regularWithApprove(let approves, let transaction) = signed else {
            return XCTFail("Expected the approve then the deposit, got \(signed)")
        }
        let expectedApproves = try THORChainSwaps().getSignedApproveTransactions(
            approvePayload: try XCTUnwrap(payload.approvePayload),
            keysignPayload: payload,
            signatures: signatures
        )
        XCTAssertEqual(approves.map(\.rawTransaction), expectedApproves.map(\.rawTransaction))
        let expectedDeposit = try ERC20Helper(coinType: .ethereum).getSignedTransaction(
            keysignPayload: payload,
            signatures: signatures,
            nonceOffset: 1
        )
        XCTAssertEqual(transaction.rawTransaction, expectedDeposit.rawTransaction)
    }

    @MainActor
    func testSignedResetVultStakeCarriesBothApprovesThenTheDepositAtTheThirdNonce() throws {
        let payload = try sdkPayload(Self.sdkStakeWithApprove, resetAllowanceFirst: true)
        let signatures = try SigningGoldenSigner.signatures(
            forImageHashes: KeysignMessageFactory(payload: payload).getKeysignMessages(),
            curve: .secp256k1
        )
        let viewModel = KeysignViewModel()
        viewModel.signatures = signatures

        let signed = try viewModel.getSignedTransaction(keysignPayload: payload)

        guard case .regularWithApprove(let approves, let transaction) = signed else {
            return XCTFail("Expected both approves then the deposit, got \(signed)")
        }
        let expectedApproves = try THORChainSwaps().getSignedApproveTransactions(
            approvePayload: try XCTUnwrap(payload.approvePayload),
            keysignPayload: payload,
            signatures: signatures
        )
        XCTAssertEqual(approves.count, 2)
        XCTAssertEqual(approves.map(\.rawTransaction), expectedApproves.map(\.rawTransaction))
        let atFourteen = try sdkPayload(Self.sdkStakeWithoutApprove, nonce: 14)
        let expectedDeposit = try ERC20Helper(coinType: .ethereum).getSignedTransaction(
            keysignPayload: atFourteen,
            signatures: signatures
        )
        XCTAssertEqual(transaction.rawTransaction, expectedDeposit.rawTransaction)
    }

    @MainActor
    func testSignedVultStakeWithoutApproveIsRegular() throws {
        let payload = try sdkPayload(Self.sdkStakeWithoutApprove)
        let signatures = try SigningGoldenSigner.signatures(
            forImageHashes: KeysignMessageFactory(payload: payload).getKeysignMessages(),
            curve: .secp256k1
        )
        let viewModel = KeysignViewModel()
        viewModel.signatures = signatures

        let signed = try viewModel.getSignedTransaction(keysignPayload: payload)

        guard case .regular(let transaction) = signed else {
            return XCTFail("Expected a single transaction, got \(signed)")
        }
        let expected = try ERC20Helper(coinType: .ethereum).getSignedTransaction(keysignPayload: payload, signatures: signatures)
        XCTAssertEqual(transaction.rawTransaction, expected.rawTransaction)
    }

    // MARK: - Plain transfers are unchanged

    func testTokenTransferStillSignsAnErc20Transfer() throws {
        for memo in [nil, "hello", "0xdeadbeef"] {
            let payload = transferPayload(amount: BigInt(1_000_000), memo: memo)

            let actual = try ERC20Helper(coinType: .ethereum).getPreSignedInputData(keysignPayload: payload)

            XCTAssertEqual(actual, try legacyTransferInput(payload).serializedData(), "memo: \(memo ?? "nil")")
        }
    }

    func testZeroAmountTransferWithoutCalldataStaysATransfer() throws {
        for memo in [nil, "hello"] {
            let payload = transferPayload(amount: .zero, memo: memo)

            let actual = try ERC20Helper(coinType: .ethereum).getPreSignedInputData(keysignPayload: payload)

            XCTAssertEqual(actual, try legacyTransferInput(payload).serializedData(), "memo: \(memo ?? "nil")")
        }
    }

    func testContractCallWithInvalidCalldataThrows() {
        let payload = transferPayload(amount: .zero, memo: "0xnothex")

        XCTAssertThrowsError(try ERC20Helper(coinType: .ethereum).getPreSignedInputData(keysignPayload: payload))
    }

    // MARK: - Fixtures

    private static let vult = "0xb788144DF611029C60b859DF47e79B7726C4DEBa"
    private static let sVult = "0x11113d7311FB8584a6e82BB126aA11D92e5fB39B"
    private static let stakeAmount = BigInt(1_500_000_000_000_000_000)

    private static let sdkStakeWithApprove = """
        Cr4BCghFdGhlcmV1bRIEVlVMVBoqMHgzMTkzQTBlYTU1MjAzODVlMjU3QmJhOEIzMGIxNjJkMjZENGJkZDVlIioweGI3ODgxNDRERjYxMTAyOUM2MGI4NTlERjQ3ZTc5Qjc3MjZDNERFQmEoEjIIdnVsdGlzaWdCQjAzYTUyNDczOWM5ODdiNmU1YjhjYjIzNDBhZDc3YjYzYTY5MjUzZDkzMTg3YWE1YjMzNGNhYjhmODE0NDcwMjY4N0oEdnVsdBIqMHgxMTExM2Q3MzExRkI4NTg0YTZlODJCQjEyNmFBMTFEOTJlNWZCMzlCGgEwKiMKCzMwMDAwMDAwMDAwEgoxMDAwMDAwMDAwGAwiBjE1MDAwMKoBigEweDJmNGYyMWUyMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMzE5M2EwZWE1NTIwMzg1ZTI1N2JiYThiMzBiMTYyZDI2ZDRiZGQ1ZTAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDE0ZDExMjBkN2IxNjAwMDDyAUEKEzE1MDAwMDAwMDAwMDAwMDAwMDASKjB4MTExMTNkNzMxMUZCODU4NGE2ZTgyQkIxMjZhQTExRDkyZTVmQjM5QvoBQjAzYTUyNDczOWM5ODdiNmU1YjhjYjIzNDBhZDc3YjYzYTY5MjUzZDkzMTg3YWE1YjMzNGNhYjhmODE0NDcwMjY4N4ICDGxvY2FsUGFydHlJRIoCBERLTFM=
        """

    private static let sdkStakeWithoutApprove = """
        Cr4BCghFdGhlcmV1bRIEVlVMVBoqMHgzMTkzQTBlYTU1MjAzODVlMjU3QmJhOEIzMGIxNjJkMjZENGJkZDVlIioweGI3ODgxNDRERjYxMTAyOUM2MGI4NTlERjQ3ZTc5Qjc3MjZDNERFQmEoEjIIdnVsdGlzaWdCQjAzYTUyNDczOWM5ODdiNmU1YjhjYjIzNDBhZDc3YjYzYTY5MjUzZDkzMTg3YWE1YjMzNGNhYjhmODE0NDcwMjY4N0oEdnVsdBIqMHgxMTExM2Q3MzExRkI4NTg0YTZlODJCQjEyNmFBMTFEOTJlNWZCMzlCGgEwKiMKCzMwMDAwMDAwMDAwEgoxMDAwMDAwMDAwGAwiBjE1MDAwMKoBigEweDJmNGYyMWUyMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMzE5M2EwZWE1NTIwMzg1ZTI1N2JiYThiMzBiMTYyZDI2ZDRiZGQ1ZTAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDE0ZDExMjBkN2IxNjAwMDD6AUIwM2E1MjQ3MzljOTg3YjZlNWI4Y2IyMzQwYWQ3N2I2M2E2OTI1M2Q5MzE4N2FhNWIzMzRjYWI4ZjgxNDQ3MDI2ODeCAgxsb2NhbFBhcnR5SUSKAgRES0xT
        """

    private func sdkPayload(_ base64: String, resetAllowanceFirst: Bool = false, nonce: Int64? = nil) throws -> KeysignPayload {
        var proto = try VSKeysignPayload(serializedBytes: XCTUnwrap(Data(base64Encoded: base64)))
        if resetAllowanceFirst {
            proto.erc20ApprovePayload.resetAllowanceFirst = true
        }
        if let nonce {
            proto.ethereumSpecific.nonce = nonce
        }
        return try KeysignPayload(proto: proto)
    }

    private func transferPayload(amount: BigInt, memo: String?) -> KeysignPayload {
        let token = SigningGoldenFactory.coin(
            chain: .ethereum, ticker: "VULT", decimals: 18,
            contractAddress: Self.vult, isNativeToken: false, curve: .secp256k1
        )
        return SigningGoldenFactory.payload(
            coin: token,
            toAddress: SigningGoldenFactory.recipient(.ethereum),
            toAmount: amount,
            chainSpecific: .Ethereum(
                maxFeePerGasWei: BigInt(30_000_000_000),
                priorityFeeWei: BigInt(1_000_000_000),
                nonce: 12,
                gasLimit: BigInt(150_000)
            ),
            memo: memo
        )
    }

    /// The transfer input as `ERC20Helper` built it before contract calls existed.
    private func legacyTransferInput(_ payload: KeysignPayload) throws -> EthereumSigningInput {
        guard case .Ethereum(let maxFeePerGasWei, let priorityFeeWei, let nonce, let gasLimit) = payload.chainSpecific else {
            throw XCTSkip("Not an Ethereum payload")
        }
        return EthereumSigningInput.with {
            $0.chainID = Data(hexString: Int64(1).hexString())!
            $0.nonce = Data(hexString: nonce.hexString())!
            $0.toAddress = payload.coin.contractAddress
            $0.transaction = EthereumTransaction.with {
                $0.erc20Transfer = EthereumTransaction.ERC20Transfer.with {
                    $0.to = payload.toAddress
                    $0.amount = payload.toAmount.serializeForEvm()
                }
            }
            $0.gasLimit = gasLimit.magnitude.serialize()
            $0.txMode = .enveloped
            $0.maxFeePerGas = maxFeePerGasWei.magnitude.serialize()
            $0.maxInclusionFeePerGas = priorityFeeWei.magnitude.serialize()
        }
    }
}
