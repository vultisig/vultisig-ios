//
//  SigningGoldenMatrix.swift
//  VultisigAppTests
//
//  The concrete vector matrix. Each entry pins one representative operation's
//  bytes-to-sign + signed transaction. See `SigningGoldenTests` for the driver
//  and the deferred-coverage notes.
//

import BigInt
import Foundation
import Tss
import WalletCore
@testable import VultisigApp

extension SigningGoldenFactory {

    /// Fixed, deterministic constants so signed bytes never depend on wall clock
    /// or network state.
    private enum Const {
        static let solanaBlockHash = "11111111111111111111111111111111" // base58 of 32 zero bytes
        static let expiration: UInt64 = 1_900_000_000
        static let polkadotGenesis = "91b171bb158e2d3848fa23a9f1c25182fb8e20313b2c1eb49219da7a70ce90c3"
        static let hash32 = "e63d3f0f2a3a3f3e2d1c0b0a09080706050403020100ffeeddccbbaa99887766"
        // 21-byte Tron address (0x41 prefix + 20 bytes), hex-encoded.
        static let tronWitness = "41e0e0f1a3a3f3e2d1c0b0a0908070605040302010"
    }

    static var all: [SigningGoldenVector] {
        sends + swaps
    }

    // MARK: - Sends

    private static var sends: [SigningGoldenVector] {
        [
            bitcoinSend,
            ethereumSend,
            erc20Send,
            thorchainSend,
            thorchainDeposit,
            cosmosSend,
            solanaSend,
            suiSignSui,
            rippleSend,
            tonSend,
            polkadotSend,
            tronSend
        ]
    }

    private static var bitcoinSend: SigningGoldenVector {
        SigningGoldenVector(
            name: "utxo_bitcoin_send",
            curve: .secp256k1,
            expectedLeaf: "UTXOChainsHelper",
            makePayload: {
                let coin = coin(chain: .bitcoin, ticker: "BTC", decimals: 8, curve: .secp256k1)
                return payload(
                    coin: coin,
                    toAddress: recipient(.bitcoin),
                    toAmount: BigInt(500_000),
                    chainSpecific: .UTXO(byteFee: 20, sendMaxAmount: false),
                    utxos: [UtxoInfo(
                        hash: "631fad872ac6bea810cf6073f02e6cbd121cac83193b79f381f711ce93b531f0",
                        amount: 1_000_000,
                        index: 0
                    )],
                    memo: "golden"
                )
            },
            imageHashes: { try UTXOChainsHelper(coin: $0.coin.coinType).getPreSignedImageHash(keysignPayload: $0) },
            signedTransaction: { .regular(try UTXOChainsHelper(coin: $0.coin.coinType).getSignedTransaction(keysignPayload: $0, signatures: $1)) }
        )
    }

    private static var ethereumSend: SigningGoldenVector {
        SigningGoldenVector(
            name: "evm_ethereum_send",
            curve: .secp256k1,
            expectedLeaf: "EVMHelper",
            makePayload: {
                let coin = coin(chain: .ethereum, ticker: "ETH", decimals: 18, curve: .secp256k1)
                return payload(
                    coin: coin,
                    toAddress: recipient(.ethereum),
                    toAmount: BigInt(1_000_000_000_000_000), // 0.001 ETH
                    chainSpecific: .Ethereum(maxFeePerGasWei: BigInt(2_000_000_000), priorityFeeWei: BigInt(1_000_000_000), nonce: 0, gasLimit: BigInt(21_000))
                )
            },
            imageHashes: { try EVMHelper.getHelper(coin: $0.coin).getPreSignedImageHash(keysignPayload: $0) },
            signedTransaction: { .regular(try EVMHelper.getHelper(coin: $0.coin).getSignedTransaction(keysignPayload: $0, signatures: $1)) }
        )
    }

    private static var erc20Send: SigningGoldenVector {
        SigningGoldenVector(
            name: "evm_erc20_usdc_send",
            curve: .secp256k1,
            expectedLeaf: "ERC20Helper",
            makePayload: {
                let coin = coin(
                    chain: .ethereum, ticker: "USDC", decimals: 6,
                    contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                    isNativeToken: false, curve: .secp256k1
                )
                return payload(
                    coin: coin,
                    toAddress: recipient(.ethereum),
                    toAmount: BigInt(1_000_000), // 1 USDC
                    chainSpecific: .Ethereum(maxFeePerGasWei: BigInt(2_000_000_000), priorityFeeWei: BigInt(1_000_000_000), nonce: 0, gasLimit: BigInt(120_000))
                )
            },
            imageHashes: { try ERC20Helper(coinType: $0.coin.coinType).getPreSignedImageHash(keysignPayload: $0) },
            signedTransaction: { .regular(try ERC20Helper(coinType: $0.coin.coinType).getSignedTransaction(keysignPayload: $0, signatures: $1)) }
        )
    }

    private static var thorchainSend: SigningGoldenVector {
        SigningGoldenVector(
            name: "thorchain_send",
            curve: .secp256k1,
            expectedLeaf: "THORChainHelper",
            makePayload: {
                let coin = coin(chain: .thorChain, ticker: "RUNE", decimals: 8, curve: .secp256k1)
                return payload(
                    coin: coin,
                    toAddress: recipient(.thorChain),
                    toAmount: BigInt(100_000_000),
                    chainSpecific: .THORChain(accountNumber: 12, sequence: 3, fee: 2_000_000, isDeposit: false)
                )
            },
            imageHashes: { try THORChainHelper.getPreSignedImageHash(keysignPayload: $0) },
            signedTransaction: { .regular(try THORChainHelper.getSignedTransaction(keysignPayload: $0, signatures: $1)) }
        )
    }

    private static var thorchainDeposit: SigningGoldenVector {
        SigningGoldenVector(
            name: "thorchain_deposit",
            curve: .secp256k1,
            expectedLeaf: "THORChainHelper",
            makePayload: {
                let coin = coin(chain: .thorChain, ticker: "RUNE", decimals: 8, curve: .secp256k1)
                return payload(
                    coin: coin,
                    toAddress: "",
                    toAmount: BigInt(50_000_000),
                    chainSpecific: .THORChain(accountNumber: 12, sequence: 4, fee: 2_000_000, isDeposit: true),
                    memo: "POOL+:THOR.RUNE"
                )
            },
            imageHashes: { try THORChainHelper.getPreSignedImageHash(keysignPayload: $0) },
            signedTransaction: { .regular(try THORChainHelper.getSignedTransaction(keysignPayload: $0, signatures: $1)) }
        )
    }

    private static var cosmosSend: SigningGoldenVector {
        SigningGoldenVector(
            name: "cosmos_gaia_send",
            curve: .secp256k1,
            expectedLeaf: "CosmosHelper",
            makePayload: {
                let coin = coin(chain: .gaiaChain, ticker: "ATOM", decimals: 6, curve: .secp256k1)
                return payload(
                    coin: coin,
                    toAddress: recipient(.gaiaChain),
                    toAmount: BigInt(1_000_000),
                    chainSpecific: .Cosmos(accountNumber: 7, sequence: 3, gas: 200_000, transactionType: 0, ibcDenomTrace: nil, gasLimit: nil)
                )
            },
            imageHashes: { try CosmosHelper.getHelper(forChain: $0.coin.chain).getPreSignedImageHash(keysignPayload: $0) },
            signedTransaction: { .regular(try CosmosHelper.getHelper(forChain: $0.coin.chain).getSignedTransaction(keysignPayload: $0, signatures: $1)) }
        )
    }

    private static var solanaSend: SigningGoldenVector {
        SigningGoldenVector(
            name: "solana_send",
            curve: .ed25519,
            expectedLeaf: "SolanaHelper",
            makePayload: {
                let coin = coin(chain: .solana, ticker: "SOL", decimals: 9, curve: .ed25519)
                return payload(
                    coin: coin,
                    toAddress: recipient(.solana),
                    toAmount: BigInt(1_000_000),
                    chainSpecific: .Solana(recentBlockHash: Const.solanaBlockHash, priorityFee: 1_000_000, priorityLimit: 100_000, fromAddressPubKey: nil, toAddressPubKey: nil, hasProgramId: false)
                )
            },
            imageHashes: { try SolanaHelper.getPreSignedImageHash(keysignPayload: $0) },
            signedTransaction: { .regular(try SolanaHelper.getSignedTransaction(keysignPayload: $0, signatures: $1)) }
        )
    }

    private static var suiSignSui: SigningGoldenVector {
        // Vector from the SDK #705 round-trip (see SuiSignSuiTests): a pre-built
        // PTB signed verbatim through SuiHelper.
        let unsignedTxMsg = "AAACAAhkAAAAAAAAAAAgW4yMD3sdSyqcPk9QYXKDlKW2x9jp8KGyw9Tl9gcYKTACAgABAQAAAQEDAAAAAAEBAFuMjA97HUsqnD5PUGFyg5SltsfY6fChssPU5fYHGCkwARERERERERERERERERERERERERERERERERERERERERERAQAAAAAAAAAgBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwdbjIwPex1LKpw+T1BhcoOUpbbH2OnwobLD1OX2BxgpMOgDAAAAAAAAwMYtAAAAAAAA"
        return SigningGoldenVector(
            name: "sui_signSui",
            curve: .ed25519,
            expectedLeaf: "SuiHelper",
            makePayload: {
                let coin = coin(chain: .sui, ticker: "SUI", decimals: 9, curve: .ed25519)
                return payload(
                    coin: coin,
                    toAddress: "",
                    toAmount: 0,
                    chainSpecific: .Sui(referenceGasPrice: 0, coins: [], gasBudget: 0),
                    signData: .signSui(SignSui(unsignedTxMsg: unsignedTxMsg))
                )
            },
            imageHashes: { try SuiHelper.getPreSignedImageHash(keysignPayload: $0) },
            signedTransaction: { .regular(try SuiHelper.getSignedTransaction(keysignPayload: $0, signatures: $1)) }
        )
    }

    private static var rippleSend: SigningGoldenVector {
        SigningGoldenVector(
            name: "ripple_send",
            curve: .secp256k1,
            expectedLeaf: "RippleHelper",
            makePayload: {
                let coin = coin(chain: .ripple, ticker: "XRP", decimals: 6, curve: .secp256k1)
                return payload(
                    coin: coin,
                    toAddress: recipient(.ripple),
                    toAmount: BigInt(1_000_000),
                    chainSpecific: .Ripple(sequence: 99, gas: 10, lastLedgerSequence: 12_345_678)
                )
            },
            imageHashes: { try RippleHelper.getPreSignedImageHash(keysignPayload: $0) },
            signedTransaction: { .regular(try RippleHelper.getSignedTransaction(keysignPayload: $0, signatures: $1)) }
        )
    }

    private static var tonSend: SigningGoldenVector {
        SigningGoldenVector(
            name: "ton_send",
            curve: .ed25519,
            expectedLeaf: "TonHelper",
            makePayload: {
                let coin = coin(chain: .ton, ticker: "TON", decimals: 9, curve: .ed25519)
                return payload(
                    coin: coin,
                    toAddress: recipient(.ton),
                    toAmount: BigInt(1_000_000_000),
                    chainSpecific: .Ton(sequenceNumber: 0, expireAt: Const.expiration, bounceable: false, sendMaxAmount: false)
                )
            },
            imageHashes: { try TonHelper.getPreSignedImageHash(keysignPayload: $0) },
            signedTransaction: { .regular(try TonHelper.getSignedTransaction(keysignPayload: $0, signatures: $1)) }
        )
    }

    private static var polkadotSend: SigningGoldenVector {
        SigningGoldenVector(
            name: "polkadot_send",
            curve: .ed25519,
            expectedLeaf: "PolkadotHelper",
            makePayload: {
                let coin = coin(chain: .polkadot, ticker: "DOT", decimals: 10, curve: .ed25519)
                return payload(
                    coin: coin,
                    toAddress: recipient(.polkadot),
                    toAmount: BigInt(10_000_000_000),
                    chainSpecific: .Polkadot(recentBlockHash: Const.polkadotGenesis, nonce: 0, currentBlockNumber: BigInt(18_000_000), specVersion: 1_002_000, transactionVersion: 26, genesisHash: Const.polkadotGenesis)
                )
            },
            imageHashes: { try PolkadotHelper.getPreSignedImageHash(keysignPayload: $0) },
            signedTransaction: { .regular(try PolkadotHelper.getSignedTransaction(keysignPayload: $0, signatures: $1)) }
        )
    }

    private static var tronSend: SigningGoldenVector {
        SigningGoldenVector(
            name: "tron_send",
            curve: .secp256k1,
            expectedLeaf: "TronHelper",
            makePayload: {
                let coin = coin(chain: .tron, ticker: "TRX", decimals: 6, curve: .secp256k1, uncompressedSecp: true)
                return payload(
                    coin: coin,
                    toAddress: recipient(.tron),
                    toAmount: BigInt(1_000_000),
                    chainSpecific: .Tron(
                        timestamp: 1_700_000_000_000,
                        expiration: 1_700_000_060_000,
                        blockHeaderTimestamp: 1_700_000_000_000,
                        blockHeaderNumber: 50_000_000,
                        blockHeaderVersion: 30,
                        blockHeaderTxTrieRoot: Const.hash32,
                        blockHeaderParentHash: Const.hash32,
                        blockHeaderWitnessAddress: Const.tronWitness,
                        gasFeeEstimation: 1_000_000
                    )
                )
            },
            imageHashes: { try TronHelper.getPreSignedImageHash(keysignPayload: $0) },
            signedTransaction: { .regular(try TronHelper.getSignedTransaction(keysignPayload: $0, signatures: $1)) }
        )
    }

    // MARK: - Swaps

    private static var swaps: [SigningGoldenVector] {
        [
            thorchainSwap,
            // Distinct router + calldata per provider so each golden pins that
            // aggregator's actual EVM swap bytes (not an identical placeholder).
            genericSwap(
                name: "swap_generic_1inch_eth", provider: .oneInch,
                router: "0x1111111254EEB25477B68fb85Ed929f73A960582",
                data: "0x12aa3caf0000000000000000000000000000000000000000000000000de0b6b3a7640000"
            ),
            genericSwap(
                name: "swap_generic_kyber_eth", provider: .kyberSwap,
                router: "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
                data: "0xe21fd0e900000000000000000000000000000000000000000000000000000000000f4240"
            ),
            genericSwap(
                name: "swap_generic_lifi_eth", provider: .lifi,
                router: "0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE",
                data: "0x4630a0d8000000000000000000000000000000000000000000000000016345785d8a0000"
            ),
            erc20ApproveSwap
        ]
    }

    private static func thorSwapPayload(from: Coin, to: Coin, amount: BigInt) -> THORChainSwapPayload {
        THORChainSwapPayload(
            fromAddress: from.address,
            fromCoin: from,
            toCoin: to,
            vaultAddress: recipient(from.chain),
            routerAddress: nil,
            fromAmount: amount,
            toAmountDecimal: 0,
            toAmountLimit: "0",
            streamingInterval: "0",
            streamingQuantity: "0",
            expirationTime: Const.expiration,
            isAffiliate: false
        )
    }

    private static var thorchainSwap: SigningGoldenVector {
        SigningGoldenVector(
            name: "swap_thorchain_rune_to_btc",
            curve: .secp256k1,
            expectedLeaf: "THORChainSwaps",
            makePayload: {
                let rune = coin(chain: .thorChain, ticker: "RUNE", decimals: 8, curve: .secp256k1)
                let btc = coin(chain: .bitcoin, ticker: "BTC", decimals: 8, curve: .secp256k1)
                let swap = thorSwapPayload(from: rune, to: btc, amount: BigInt(100_000_000))
                return payload(
                    coin: rune,
                    toAddress: swap.vaultAddress,
                    toAmount: BigInt(100_000_000),
                    chainSpecific: .THORChain(accountNumber: 12, sequence: 3, fee: 2_000_000, isDeposit: true),
                    memo: "=:BTC.BTC:\(recipient(.bitcoin)):0/1/0",
                    swapPayload: .thorchain(swap)
                )
            },
            imageHashes: {
                guard case .thorchain(let swap) = $0.swapPayload else { throw SigningGoldenError.missingSwapPayload }
                return try THORChainSwaps().getPreSignedImageHash(swapPayload: swap, keysignPayload: $0, incrementNonce: false)
            },
            signedTransaction: {
                guard case .thorchain(let swap) = $0.swapPayload else { throw SigningGoldenError.missingSwapPayload }
                return .regular(try THORChainSwaps().getSignedTransaction(swapPayload: swap, keysignPayload: $0, signatures: $1, incrementNonce: false))
            }
        )
    }

    private static func genericSwap(name: String, provider: SwapProviderId, router: String, data: String) -> SigningGoldenVector {
        SigningGoldenVector(
            name: name,
            curve: .secp256k1,
            expectedLeaf: "OneInchSwaps",
            makePayload: {
                let eth = coin(chain: .ethereum, ticker: "ETH", decimals: 18, curve: .secp256k1)
                let usdc = coin(
                    chain: .ethereum, ticker: "USDC", decimals: 6,
                    contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                    isNativeToken: false, curve: .secp256k1
                )
                let quote = EVMQuote(
                    dstAmount: "2500000000",
                    tx: EVMQuote.Transaction(
                        from: eth.address, to: router, data: data,
                        value: "1000000000000000", gasPrice: "2000000000", gas: 600_000
                    )
                )
                let generic = GenericSwapPayload(
                    fromCoin: eth, toCoin: usdc, fromAmount: BigInt(1_000_000_000_000_000),
                    toAmountDecimal: 0, quote: quote, provider: provider
                )
                return payload(
                    coin: eth,
                    toAddress: router,
                    toAmount: BigInt(1_000_000_000_000_000),
                    chainSpecific: .Ethereum(maxFeePerGasWei: BigInt(2_000_000_000), priorityFeeWei: BigInt(1_000_000_000), nonce: 0, gasLimit: BigInt(600_000)),
                    swapPayload: .generic(generic)
                )
            },
            imageHashes: {
                guard case .generic(let swap) = $0.swapPayload else { throw SigningGoldenError.missingSwapPayload }
                return try OneInchSwaps().getPreSignedImageHash(payload: swap, keysignPayload: $0, incrementNonce: false)
            },
            signedTransaction: {
                guard case .generic(let swap) = $0.swapPayload else { throw SigningGoldenError.missingSwapPayload }
                return .regular(try OneInchSwaps().getSignedTransaction(payload: swap, keysignPayload: $0, signatures: $1, incrementNonce: false))
            }
        )
    }

    private static var erc20ApproveSwap: SigningGoldenVector {
        SigningGoldenVector(
            name: "swap_erc20_approve_1inch",
            curve: .secp256k1,
            expectedLeaf: "THORChainSwaps.approve + OneInchSwaps",
            makePayload: {
                let usdc = coin(
                    chain: .ethereum, ticker: "USDC", decimals: 6,
                    contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                    isNativeToken: false, curve: .secp256k1
                )
                let eth = coin(chain: .ethereum, ticker: "ETH", decimals: 18, curve: .secp256k1)
                let router = "0x1111111254EEB25477B68fb85Ed929f73A960582"
                let quote = EVMQuote(
                    dstAmount: "500000000000000",
                    tx: EVMQuote.Transaction(
                        from: usdc.address, to: router,
                        data: "0x12aa3caf0000000000000000000000000000000000000000000000000000000000000001",
                        value: "0", gasPrice: "2000000000", gas: 600_000
                    )
                )
                let generic = GenericSwapPayload(
                    fromCoin: usdc, toCoin: eth, fromAmount: BigInt(1_000_000),
                    toAmountDecimal: 0, quote: quote, provider: .oneInch
                )
                return payload(
                    coin: usdc,
                    toAddress: router,
                    toAmount: BigInt(1_000_000),
                    chainSpecific: .Ethereum(maxFeePerGasWei: BigInt(2_000_000_000), priorityFeeWei: BigInt(1_000_000_000), nonce: 0, gasLimit: BigInt(600_000)),
                    swapPayload: .generic(generic),
                    approvePayload: ERC20ApprovePayload(amount: BigInt(1_000_000), spender: router)
                )
            },
            imageHashes: {
                guard case .generic(let swap) = $0.swapPayload,
                      let approve = $0.approvePayload else { throw SigningGoldenError.missingSwapPayload }
                let approveHashes = try THORChainSwaps().getPreSignedApproveImageHash(approvePayload: approve, keysignPayload: $0)
                let swapHashes = try OneInchSwaps().getPreSignedImageHash(payload: swap, keysignPayload: $0, incrementNonce: true)
                return approveHashes + swapHashes
            },
            signedTransaction: {
                guard case .generic(let swap) = $0.swapPayload,
                      let approve = $0.approvePayload else { throw SigningGoldenError.missingSwapPayload }
                let approveTx = try THORChainSwaps().getSignedApproveTransaction(approvePayload: approve, keysignPayload: $0, signatures: $1)
                let swapTx = try OneInchSwaps().getSignedTransaction(payload: swap, keysignPayload: $0, signatures: $1, incrementNonce: true)
                return .regularWithApprove(approve: approveTx, transaction: swapTx)
            }
        )
    }

}

enum SigningGoldenError: Error {
    case missingSwapPayload
}
