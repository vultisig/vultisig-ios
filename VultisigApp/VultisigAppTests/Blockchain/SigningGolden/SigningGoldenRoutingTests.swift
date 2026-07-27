//
//  SigningGoldenRoutingTests.swift
//  VultisigAppTests
//
//  A readable, self-contained mirror of the `KeysignViewModel.getSignedTransaction`
//  routing keys (the S4 dispatch: swapPayload → leaf, then chainType → leaf).
//  It documents the routing CONTRACT and fails if a vector's declared
//  `expectedLeaf` no longer matches the dispatch this mirror encodes.
//
//  This complements `SigningGoldenTests.testDispatcherRoutesToExpectedLeaf`,
//  which proves at RUNTIME (byte-equality) that the real dispatcher reaches the
//  same leaf. Together: one asserts the contract, the other proves it.
//

import BigInt
import XCTest
@testable import VultisigApp

final class SigningGoldenRoutingTests: XCTestCase {

    func testRoutingContractMatchesDeclaredLeaf() throws {
        for vector in SigningGoldenFactory.all {
            let payload = try vector.makePayload()
            XCTAssertEqual(
                Self.expectedLeaf(for: payload),
                vector.expectedLeaf,
                "\(vector.name): routing-contract mirror disagrees with the vector's declared leaf"
            )
        }
    }

    /// The deferred families (Maya, SwapKit) have no byte-golden vector, but the
    /// routing CONTRACT for them must still be exercised — otherwise the mirror's
    /// Maya fall-through and SwapKit branches are dead. Build synthetic payloads
    /// (no signing) and pin the leaf each routes to.
    func testRoutingContractCoversDeferredFamilies() {
        let btc = SigningGoldenFactory.coin(chain: .bitcoin, ticker: "BTC", decimals: 8, curve: .secp256k1)
        let cacao = SigningGoldenFactory.coin(chain: .mayaChain, ticker: "CACAO", decimals: 10, curve: .secp256k1)
        let usdc = SigningGoldenFactory.coin(
            chain: .ethereum, ticker: "USDC", decimals: 6,
            contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            isNativeToken: false, curve: .secp256k1
        )

        func mayaSwapPayload(from: Coin) -> THORChainSwapPayload {
            THORChainSwapPayload(
                fromAddress: from.address, fromCoin: from, toCoin: btc,
                vaultAddress: "", routerAddress: nil, fromAmount: BigInt(0),
                toAmountDecimal: 0, toAmountLimit: "0", streamingInterval: "0",
                streamingQuantity: "0", expirationTime: 0, isAffiliate: false
            )
        }

        // Maya on a native (non-EVM) source falls through to the per-chain Maya helper.
        let mayaNative = SigningGoldenFactory.payload(
            coin: cacao, toAddress: "", toAmount: BigInt(0),
            chainSpecific: .MayaChain(accountNumber: 0, sequence: 0, isDeposit: true),
            swapPayload: .mayachain(mayaSwapPayload(from: cacao))
        )
        XCTAssertEqual(Self.expectedLeaf(for: mayaNative), "MayaChainHelper")

        // Maya on an EVM token routes to THORChainSwaps.
        let mayaEvmToken = SigningGoldenFactory.payload(
            coin: usdc, toAddress: "", toAmount: BigInt(0),
            chainSpecific: .Ethereum(maxFeePerGasWei: BigInt(0), priorityFeeWei: BigInt(0), nonce: 0, gasLimit: BigInt(0)),
            swapPayload: .mayachain(mayaSwapPayload(from: usdc))
        )
        XCTAssertEqual(Self.expectedLeaf(for: mayaEvmToken), "THORChainSwaps")

        // A SwapKit (non-EVM) route dispatches to the SwapKit signer family.
        let swapkitPayload = SwapKitSwapPayload(
            fromCoin: btc, toCoin: usdc, fromAmount: BigInt(0), toAmountDecimal: 0,
            txType: "PSBT", txPayload: Data(), targetAddress: "",
            inboundAddress: nil, memo: nil, subProvider: "", swapID: ""
        )
        let swapkit = SigningGoldenFactory.payload(
            coin: btc, toAddress: "", toAmount: BigInt(0),
            chainSpecific: .UTXO(byteFee: BigInt(0), sendMaxAmount: false),
            swapPayload: .swapkit(swapkitPayload)
        )
        XCTAssertEqual(Self.expectedLeaf(for: swapkit), "SwapKitSigner")
    }

    /// Mirrors `KeysignViewModel.getSignedTransaction`'s dispatch order:
    /// approve leg first, then the swap switch, then the per-chain switch.
    static func expectedLeaf(for payload: KeysignPayload) -> String {
        if payload.approvePayload != nil {
            return "THORChainSwaps.approve + \(swapLeaf(payload) ?? perChainLeaf(payload))"
        }
        if let leaf = swapLeaf(payload) {
            return leaf
        }
        return perChainLeaf(payload)
    }

    /// The leaf a swapPayload routes to, or nil when the swap falls through to
    /// the per-chain helper (Maya on a native / non-EVM source).
    private static func swapLeaf(_ payload: KeysignPayload) -> String? {
        guard let swap = payload.swapPayload else { return nil }
        switch swap {
        case .thorchain, .thorchainChainnet, .thorchainStagenet:
            return "THORChainSwaps"
        case .generic:
            return payload.coin.chain == .solana ? "SolanaSwaps" : "OneInchSwaps"
        case .mayachain:
            if payload.coin.chainType == .EVM && !payload.coin.isNativeToken {
                return "THORChainSwaps"
            }
            return nil // falls through to the per-chain (Maya) helper
        case .swapkit:
            return "SwapKitSigner"
        }
    }

    private static func perChainLeaf(_ payload: KeysignPayload) -> String {
        switch payload.coin.chain.chainType {
        case .UTXO:
            return "UTXOChainsHelper"
        case .Cardano:
            return "CardanoHelper"
        case .EVM:
            return payload.coin.isNativeToken ? "EVMHelper" : "ERC20Helper"
        case .THORChain:
            return payload.coin.chain == .mayaChain ? "MayaChainHelper" : "THORChainHelper"
        case .Solana:
            return "SolanaHelper"
        case .Sui:
            return "SuiHelper"
        case .Polkadot:
            return payload.coin.chain == .bittensor ? "BittensorHelper" : "PolkadotHelper"
        case .Cosmos:
            return "CosmosHelper"
        case .Ton:
            return "TonHelper"
        case .Ripple:
            return "RippleHelper"
        case .Tron:
            return "TronHelper"
        }
    }
}
