//
//  SignedTransactionContent.swift
//  VultisigApp
//
//  A shared, deliberately narrow view of what initiators and co-signers sign.
//  It excludes display metadata, hides sidecars when opaque content is active,
//  and mirrors the signer's routing precedence.
//

import BigInt
import Foundation
import VultisigCommonData

/// The quantity a transaction moves, or the fact that it does not carry one.
enum SignedAmount: Hashable {

    /// Base units carried by the transaction.
    case committed(BigInt)

    /// A max-send amount derived from balance and fee during signing. No preview
    /// value is exposed to decoders.
    case computedAtSigning
}

/// How a chain's grammar relates to the routes that are signed before its own
/// helper runs.
/// There is no default: every memo reader must state its precedence.
enum MemoPrecedence {

    /// An earlier approve or swap route makes the sidecar memo inert.
    case memoIsInertWhenRoutedEarlier

    /// The earlier route carries the memo into the signed transaction.
    case memoTravelsWithTheEarlierRoute
}

struct CorroboratedContent {
    /// Available only when opaque signed content does not supersede sidecars.
    let toAddress: String
    let amount: SignedAmount
    /// Private so callers must state memo precedence.
    private let rawMemo: String?
    let transactionType: VSTransactionType
    let wasmPayload: WasmExecuteContractPayload?
    let swap: SwapPayload?
    let approve: ERC20ApprovePayload?

    init(
        toAddress: String,
        amount: SignedAmount,
        rawMemo: String?,
        transactionType: VSTransactionType,
        wasmPayload: WasmExecuteContractPayload?,
        swap: SwapPayload?,
        approve: ERC20ApprovePayload?
    ) {
        self.toAddress = toAddress
        self.amount = amount
        self.rawMemo = rawMemo
        self.transactionType = transactionType
        self.wasmPayload = wasmPayload
        self.swap = swap
        self.approve = approve
    }

    /// Returns the memo only when the reader's precedence permits it.
    func memo(_ precedence: MemoPrecedence) -> String? {
        switch precedence {
        case .memoIsInertWhenRoutedEarlier:
            return routedBeforeTheChainHelper ? nil : rawMemo
        case .memoTravelsWithTheEarlierRoute:
            return rawMemo
        }
    }
}

protocol SignedTransactionContent {

    /// The signed chain scope. Display-only `Coin` metadata stays out of reach.
    var chain: Chain { get }

    /// Whether the chain settles the moved asset as its native coin.
    var isNativeCoin: Bool { get }

    // MARK: Ungated fields
    // Decoders should prefer `corroborated`; `raw` access requires explicit proof.

    var rawToAddress: String { get }

    /// The quantity, or the fact that the signer computes it.
    var rawAmount: SignedAmount { get }

    var signedData: SignData? { get }

    /// Whether `signDirect.bodyBytes` is the active body consumed by the signer.
    /// Approve, swap, and rebuilt Cosmos routes can make it inactive.
    var signedDataBodyIsActive: Bool { get }

    /// Whether opaque signed content supersedes all flat sidecar fields. Both
    /// devices report this from the representation they hold.
    var hasOpaqueSignedContent: Bool { get }

    var rawMemo: String? { get }
    var rawTransactionType: VSTransactionType { get }
    var rawWasmPayload: WasmExecuteContractPayload? { get }
    var rawSwap: SwapPayload? { get }
    var rawApprove: ERC20ApprovePayload? { get }

    /// A Solana pre-image the initiator's signer will encode. Co-signers have
    /// signed bytes instead and return `nil`.
    var stakingIntent: SolanaStakingPayload? { get }

    /// The Cosmos staking structure that the initiator's signing path will turn
    /// into a SignDoc. A co-signer answers `nil` and reads that SignDoc instead.
    var cosmosStakingIntent: CosmosStakingPayload? { get }

    /// Whether an earlier signing route makes the memo inert.
    var memoIsOutranked: Bool { get }
}

extension CorroboratedContent {

    /// Approve and swap routes run before chain helpers. Each memo reader decides
    /// whether that makes its memo inert; THORChain swaps carry theirs forward.
    var routedBeforeTheChainHelper: Bool {
        swap != nil || approve != nil
    }
}

extension SignedTransactionContent {

    var signedDataBodyIsActive: Bool { false }

    /// Wasm outranks the memo everywhere it appears; chains with further
    /// precedence of their own say so by overriding this.
    var memoIsOutranked: Bool { rawWasmPayload != nil }

    /// A coherent set of sidecars, withheld together when opaque content wins.
    var corroborated: CorroboratedContent? {
        guard !hasOpaqueSignedContent else { return nil }

        let wasm = rawWasmPayload

        return CorroboratedContent(
            toAddress: rawToAddress,
            amount: rawAmount,
            // Wasm and chain-specific higher-priority routes make sidecar memos inert.
            rawMemo: memoIsOutranked ? nil : rawMemo,
            transactionType: rawTransactionType,
            wasmPayload: wasm,
            swap: rawSwap,
            approve: rawApprove
        )
    }
}

// MARK: - A co-signer's view

extension KeysignPayload: SignedTransactionContent {

    var chain: Chain { coin.chain }

    var isNativeCoin: Bool { coin.isNativeToken }

    var rawToAddress: String { toAddress }

    var rawAmount: SignedAmount {
        chainSpecific.sendsMaxAmount ? .computedAtSigning : .committed(toAmount)
    }

    var rawMemo: String? {
        guard let memo, !memo.isEmpty else { return nil }
        return memo
    }

    var rawTransactionType: VSTransactionType { chainSpecific.transactionType }

    var rawWasmPayload: WasmExecuteContractPayload? { wasmExecuteContractPayload }

    var rawSwap: SwapPayload? { swapPayload }

    var rawApprove: ERC20ApprovePayload? { approvePayload }

    var signedData: SignData? { signData }

    var signedDataBodyIsActive: Bool {
        guard case .signDirect? = signData,
              approvePayload == nil,
              swapPayload == nil
        else { return false }

        switch coin.chain {
        case .gaiaChain, .kujira, .osmosis, .noble, .akash:
            switch chainSpecific.transactionType {
            case .unspecified, .genericContract:
                return true
            default:
                return false
            }
        case .terra, .terraClassic:
            return true
        case .dydx:
            return chainSpecific.transactionType != .vote
        case .qbtc:
            return true
        default:
            return false
        }
    }

    var hasOpaqueSignedContent: Bool { signData != nil }

    var stakingIntent: SolanaStakingPayload? { nil }

    var cosmosStakingIntent: CosmosStakingPayload? { nil }

    /// Mirrors TRON signing precedence: typed contracts outrank staking memos.
    var memoIsOutranked: Bool {
        rawWasmPayload != nil
            || tronTransferContractPayload != nil
            || tronTriggerSmartContractPayload != nil
            || tronTransferAssetContractPayload != nil
    }
}

// MARK: - An initiator's view

/// The initiator's pre-payload transaction viewed through the same decoder API.
/// Structured staking intents are exposed because the signer builds from them.
struct InitiatingTransactionContent: SignedTransactionContent {

    let transaction: SendTransaction

    init(_ transaction: SendTransaction) {
        self.transaction = transaction
    }

    var chain: Chain { transaction.coin.chain }

    var isNativeCoin: Bool { transaction.coin.isNativeToken }

    var rawToAddress: String { transaction.toAddress }

    /// Max and auto-adjusted amounts are still changing and cannot be stated.
    var rawAmount: SignedAmount {
        let refitted = transaction.sendMaxAmount || transaction.amountWasAutoAdjusted
        return refitted ? .computedAtSigning : .committed(transaction.amountInRaw)
    }

    var rawMemo: String? {
        transaction.memo.isEmpty ? nil : transaction.memo
    }

    var rawTransactionType: VSTransactionType { transaction.transactionType }

    var rawWasmPayload: WasmExecuteContractPayload? { transaction.wasmContractPayload }

    var rawSwap: SwapPayload? { nil }

    var rawApprove: ERC20ApprovePayload? { nil }

    var signedData: SignData? { nil }

    var stakingIntent: SolanaStakingPayload? { transaction.solanaStakingPayload }

    var cosmosStakingIntent: CosmosStakingPayload? { transaction.cosmosStakingPayload }

    /// Staking intents become opaque signed content when the payload is built.
    var hasOpaqueSignedContent: Bool {
        transaction.cosmosStakingPayload != nil || transaction.solanaStakingPayload != nil
    }
}

// MARK: - Reading the chain-specific case

extension BlockChainSpecific {

    /// Whether signing derives the amount from balance and fee.
    var sendsMaxAmount: Bool {
        switch self {
        case .UTXO(_, let sendMaxAmount, _): return sendMaxAmount
        case .Cardano(_, let sendMaxAmount, _): return sendMaxAmount
        case .Ton(_, _, _, let sendMaxAmount, _, _): return sendMaxAmount
        default: return false
        }
    }

    /// The wire discriminator, or `.unspecified` when the chain carries none.
    var transactionType: VSTransactionType {
        switch self {
        case .THORChain(_, _, _, _, let transactionType):
            return VSTransactionType(rawValue: transactionType) ?? .unspecified
        case .Cosmos(_, _, _, let transactionType, _, _):
            return VSTransactionType(rawValue: transactionType) ?? .unspecified
        case .Ripple(_, _, _, _, let transactionType):
            return VSTransactionType(rawValue: transactionType) ?? .unspecified
        case .UTXO, .Cardano, .Ethereum, .MayaChain, .Solana, .Sui,
             .Polkadot, .Ton, .Tron:
            return .unspecified
        }
    }
}
