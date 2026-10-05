//
//  ERC20SelfTransferGuardTests.swift
//  VultisigAppTests
//
//  An ERC-20 transfer addressed to the token's own contract burns the tokens, so
//  every signer refuses it from the relayed payload, whatever the address casing.
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

final class ERC20SelfTransferGuardTests: XCTestCase {
    private let hexPublicKey = "023e4b76861289ad4528b33c2fd21b3a5160cd37b3294234914e21efb6ed4a452b"
    private let hexChainCode = "c9b189a8232b872b8d9ccd867d0db316dd10f56e729c310fe072adf5fd204ae7"
    private let recipient = "0xfA0635a1d083D0bF377EFbD48DA46BB17e0106cA"

    private func makePayload(toAddress: String) throws -> KeysignPayload {
        let usdc = try CoinFactory.create(
            asset: TokensStore.Token.ethereumUsdc,
            publicKeyECDSA: hexPublicKey,
            publicKeyEdDSA: "",
            hexChainCode: hexChainCode,
            isDerived: false
        )
        return KeysignPayload(
            coin: usdc,
            toAddress: toAddress,
            toAmount: 8000,
            chainSpecific: BlockChainSpecific.Ethereum(
                maxFeePerGasWei: BigInt(10),
                priorityFeeWei: BigInt(1),
                nonce: 0,
                gasLimit: BigInt(120000)
            ),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "ECDSAKey",
            vaultLocalPartyID: "localPartyID",
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

    func testTransferToOwnContractIsRefused() throws {
        let contract = TokensStore.Token.ethereumUsdc.contractAddress
        let payload = try makePayload(toAddress: contract)
        XCTAssertThrowsError(try ERC20Helper(coinType: .ethereum).getPreSignedInputData(keysignPayload: payload))
    }

    func testTransferToOwnContractIsRefusedRegardlessOfCasing() throws {
        let contract = TokensStore.Token.ethereumUsdc.contractAddress
        for variant in [contract.lowercased(), "0x" + contract.dropFirst(2).uppercased()] {
            let payload = try makePayload(toAddress: variant)
            XCTAssertThrowsError(
                try ERC20Helper(coinType: .ethereum).getPreSignedImageHash(keysignPayload: payload),
                "\(variant) must be refused"
            )
        }
    }

    func testTransferToOrdinaryRecipientIsAccepted() throws {
        let payload = try makePayload(toAddress: recipient)
        let data = try ERC20Helper(coinType: .ethereum).getPreSignedInputData(keysignPayload: payload)
        let input = try EthereumSigningInput(serializedBytes: data)
        XCTAssertEqual(input.transaction.erc20Transfer.to, recipient)
    }
}
