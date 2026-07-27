//
//  SigningGoldenFixtures.swift
//  VultisigAppTests
//
//  The curated, extensible fixture matrix for the signing-pipeline golden
//  harness: one representative vector per chain-family send, plus swaps per
//  provider and an ERC20 approve+swap. Each vector is self-describing —
//  it knows how to build its `KeysignPayload`, which curve signs it, how to
//  reach its leaf `getPreSignedImageHash` / `getSignedTransaction` seam, and
//  which leaf the `KeysignViewModel` dispatcher is expected to route it to
//  (the S4 contract).
//
//  Adding a vector = appending one `SigningGoldenVector` here (and recording
//  its golden). Nothing else changes.
//

import BigInt
import Foundation
import Tss
import WalletCore
@testable import VultisigApp

/// One golden vector: an operation whose signed bytes must not drift.
struct SigningGoldenVector {
    let name: String
    /// Which fixed key + signature encoding the vector uses.
    let curve: SigningGoldenCurve
    /// Human-readable leaf the S4 dispatcher must route this payload to. Pinned
    /// by `SigningGoldenRoutingTests` against a mirror of the dispatcher keys.
    let expectedLeaf: String
    /// Builds the payload fresh each call (coins are reference types).
    let makePayload: () throws -> KeysignPayload
    /// The bytes-to-sign via the direct leaf `getPreSignedImageHash`.
    let imageHashes: (KeysignPayload) throws -> [String]
    /// The signed transaction via the direct leaf `getSignedTransaction`,
    /// assembled into the same `SignedTransactionType` the dispatcher returns.
    let signedTransaction: (KeysignPayload, [String: TssKeysignResponse]) throws -> SignedTransactionType
    /// Whether the runtime `KeysignViewModel.getSignedTransaction` routing-parity
    /// assertion applies (true for everything the VM can construct + route).
    let assertsDispatcherParity: Bool

    init(
        name: String,
        curve: SigningGoldenCurve,
        expectedLeaf: String,
        assertsDispatcherParity: Bool = true,
        makePayload: @escaping () throws -> KeysignPayload,
        imageHashes: @escaping (KeysignPayload) throws -> [String],
        signedTransaction: @escaping (KeysignPayload, [String: TssKeysignResponse]) throws -> SignedTransactionType
    ) {
        self.name = name
        self.curve = curve
        self.expectedLeaf = expectedLeaf
        self.assertsDispatcherParity = assertsDispatcherParity
        self.makePayload = makePayload
        self.imageHashes = imageHashes
        self.signedTransaction = signedTransaction
    }
}

/// Coin / payload construction shared across vectors.
enum SigningGoldenFactory {

    /// A distinct deterministic recipient key (valid on both curves).
    private static let recipientKey: PrivateKey = {
        guard let key = PrivateKey(data: Data(repeating: 0x42, count: 32)) else {
            fatalError("SigningGoldenFactory: invalid recipient key")
        }
        return key
    }()

    /// Canonical destination address for `chain`, derived from a fixed key so
    /// it is a real, chain-valid address (never a placeholder string).
    static func recipient(_ chain: Chain) -> String {
        chain.coinType.deriveAddress(privateKey: recipientKey)
    }

    /// A signing coin whose `address` + `hexPublicKey` both derive from the
    /// vector's fixed key, so synthesized signatures verify. `uncompressedSecp`
    /// is required for Tron (WalletCore builds a `.secp256k1Extended` key).
    static func coin(
        chain: Chain,
        ticker: String,
        decimals: Int,
        contractAddress: String = "",
        isNativeToken: Bool = true,
        curve: SigningGoldenCurve,
        uncompressedSecp: Bool = false
    ) -> Coin {
        let key = SigningGoldenSigner.privateKey(for: curve)
        let address = chain.coinType.deriveAddress(privateKey: key)
        let hexPublicKey: String
        switch curve {
        case .ed25519:
            hexPublicKey = key.getPublicKeyEd25519().data.hexString
        case .secp256k1:
            hexPublicKey = key.getPublicKeySecp256k1(compressed: !uncompressedSecp).data.hexString
        }
        let meta = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: ticker.lowercased(),
            decimals: decimals,
            priceProviderId: ticker.lowercased(),
            contractAddress: contractAddress,
            isNativeToken: isNativeToken
        )
        return Coin(asset: meta, address: address, hexPublicKey: hexPublicKey)
    }

    /// A `KeysignPayload` with the boilerplate (nil contract payloads,
    /// `libType`, etc.) filled in; callers vary only the load-bearing fields.
    static func payload(
        coin: Coin,
        toAddress: String,
        toAmount: BigInt,
        chainSpecific: BlockChainSpecific,
        utxos: [UtxoInfo] = [],
        memo: String? = nil,
        swapPayload: SwapPayload? = nil,
        approvePayload: ERC20ApprovePayload? = nil,
        signData: SignData? = nil
    ) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: toAddress,
            toAmount: toAmount,
            chainSpecific: chainSpecific,
            utxos: utxos,
            memo: memo,
            swapPayload: swapPayload,
            approvePayload: approvePayload,
            vaultPubKeyECDSA: SigningGoldenSigner.publicKeyHex(for: .secp256k1),
            vaultLocalPartyID: "localPartyID",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: signData
        )
    }
}
