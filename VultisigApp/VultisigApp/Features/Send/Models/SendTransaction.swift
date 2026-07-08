//
//  SendTransaction.swift
//  VultisigApp
//
//  Immutable hand-off from `SendDetailsViewModel` to the rest of the send
//  flow. Constructed only when the user taps "Continue" and validation
//  passes; consumers (Verify / Pair / Keysign / Done) read it but never
//  mutate it. Form-time mutation lives on the details VM.
//
//  Replaces the legacy `class FunctionCallForm: ObservableObject` —
//  see [[projects/vultisig/transaction-model-refactor/send-pilot-plan]] for
//  the three kickoff decisions baked in:
//    1. `memoFunctionDictionary` is a plain `[String: String]` (the immutable
//       struct is the thread-safety boundary; no `ThreadSafeDictionary`).
//    2. `vault` is required (`Vault`, not `Vault?`).
//    3. `customGasLimit` / `customByteFee` are first-class fields so the
//       Verify refresh path can preserve them — the legacy
//       `SendCryptoVerifyLogic` dropped the user's pinned gas on refresh.
//

import BigInt
import Foundation
import VultisigCommonData

struct SendDetailsSeed: Hashable {
    let coin: Coin
    let vault: Vault
    let hasPreselectedCoin: Bool

    let fromAddress: String
    let toAddress: String
    let toAddressLabel: String?
    let lastResolvedAddress: String?
    let amount: String
    let amountInFiat: String
    let memo: String
    let gas: BigInt
    let fee: BigInt
    let feeMode: FeeMode
    let estimatedGasLimit: BigInt?
    let customGasLimit: BigInt?
    let customByteFee: BigInt?
    let sendMaxAmount: Bool
    let isStakingOperation: Bool
    let transactionType: VSTransactionType
    let memoFunctionDictionary: [String: String]
    let wasmContractPayload: WasmExecuteContractPayload?

    static func empty(coin: Coin, vault: Vault, hasPreselectedCoin: Bool) -> SendDetailsSeed {
        SendDetailsSeed(
            coin: coin,
            vault: vault,
            hasPreselectedCoin: hasPreselectedCoin,
            fromAddress: coin.address,
            toAddress: "",
            toAddressLabel: nil,
            lastResolvedAddress: nil,
            amount: "",
            amountInFiat: "",
            memo: "",
            gas: .zero,
            fee: .zero,
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil
        )
    }

    /// Builds an empty seed prefilled with the deeplink/scanner fields used
    /// by `HomeRouteBuilder` when routing `VaultAction.send` so the prefill
    /// rides on the route value instead of mutating a long-lived form.
    static func fromAction(
        coin: Coin,
        vault: Vault,
        hasPreselectedCoin: Bool,
        prefilledToAddress: String?,
        prefilledAmount: String?,
        prefilledMemo: String?
    ) -> SendDetailsSeed {
        SendDetailsSeed(
            coin: coin,
            vault: vault,
            hasPreselectedCoin: hasPreselectedCoin,
            fromAddress: coin.address,
            toAddress: prefilledToAddress ?? "",
            toAddressLabel: nil,
            lastResolvedAddress: nil,
            amount: prefilledAmount ?? "",
            amountInFiat: "",
            memo: prefilledMemo ?? "",
            gas: .zero,
            fee: .zero,
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil
        )
    }
}

struct SendCoinSnapshot: Hashable {
    let chain: Chain
    let ticker: String
    let decimals: Int
    let priceProviderId: String
    let contractAddress: String
    let isNativeToken: Bool
    let address: String
    let rawBalance: String

    init(coin: Coin) {
        chain = coin.chain
        ticker = coin.ticker
        decimals = coin.decimals
        priceProviderId = coin.priceProviderId
        contractAddress = coin.contractAddress
        isNativeToken = coin.isNativeToken
        address = coin.address
        rawBalance = coin.rawBalance
    }
}

struct SendVaultSnapshot: Hashable {
    let pubKeyECDSA: String
    let pubKeyEdDSA: String
    let localPartyID: String
    let hexChainCode: String

    init(vault: Vault) {
        pubKeyECDSA = vault.pubKeyECDSA
        pubKeyEdDSA = vault.pubKeyEdDSA
        localPartyID = vault.localPartyID
        hexChainCode = vault.hexChainCode
    }
}

enum SendTransactionUpdate<Value> {
    case set(Value)

    var value: Value {
        switch self {
        case .set(let value):
            return value
        }
    }
}

struct SendTransaction: Hashable {
    // Identity
    let coin: Coin
    let vault: Vault
    let coinSnapshot: SendCoinSnapshot
    let vaultSnapshot: SendVaultSnapshot

    // Form fields
    let fromAddress: String
    let toAddress: String
    let toAddressLabel: String?
    let amount: String
    let amountInFiat: String
    let memo: String

    /// XRP destination tag (nil elsewhere / when absent). Carried separately
    /// from `memo` so the Verify screen can show an honest "Destination Tag"
    /// row; the keysign payload encodes it into the memo slot as a canonical
    /// uint32 decimal — the cross-platform wire contract (`RippleDestinationTag`).
    let destinationTag: UInt32?

    // Fee / gas
    let gas: BigInt
    let fee: BigInt
    let feeMode: FeeMode
    let estimatedGasLimit: BigInt?
    let customGasLimit: BigInt?
    let customByteFee: BigInt?

    // Mode flags
    let sendMaxAmount: Bool
    let isStakingOperation: Bool
    let transactionType: VSTransactionType

    // Function-call side channels (kept as plain fields for the Send pilot;
    // first-class case-enum modelling lands in Functions §13).
    let memoFunctionDictionary: [String: String]
    let wasmContractPayload: WasmExecuteContractPayload?

    /// Native coin that pays for gas — `coin` itself for native sends, the
    /// chain's native sibling (e.g. ETH for a USDC source) otherwise.
    /// Precomputed at construction so Verify/Done don't need the vault's
    /// full coin list at read time.
    let feeCoin: Coin
    let feeCoinSnapshot: SendCoinSnapshot

    /// Cosmos-SDK x/staking + x/distribution operation intent. Non-nil only
    /// for LUNA / LUNC delegate / undelegate / redelegate / claim flows;
    /// populated by the per-flow `TransactionBuilder` and consumed by the
    /// Verify → KeysignPayload bridge to produce the SignDoc bytes.
    /// Local-only on iOS — does not round-trip through the proto-mappable
    /// `KeysignMessage` bridge (same posture as `qbtcClaimPayload`).
    let cosmosStakingPayload: CosmosStakingPayload?

    /// Solana native-staking operation intent. Non-nil only for the Solana
    /// delegate flow; populated by the per-flow `TransactionBuilder` and
    /// consumed by the Verify → KeysignPayload bridge to produce the unsigned
    /// transaction bytes. Local-only on iOS — same posture as
    /// `cosmosStakingPayload`.
    let solanaStakingPayload: SolanaStakingPayload?
}

extension SendTransaction {
    static func == (lhs: SendTransaction, rhs: SendTransaction) -> Bool {
        lhs.coinSnapshot == rhs.coinSnapshot &&
            lhs.vaultSnapshot == rhs.vaultSnapshot &&
            lhs.fromAddress == rhs.fromAddress &&
            lhs.toAddress == rhs.toAddress &&
            lhs.toAddressLabel == rhs.toAddressLabel &&
            lhs.amount == rhs.amount &&
            lhs.amountInFiat == rhs.amountInFiat &&
            lhs.memo == rhs.memo &&
            lhs.destinationTag == rhs.destinationTag &&
            lhs.gas == rhs.gas &&
            lhs.fee == rhs.fee &&
            lhs.feeMode == rhs.feeMode &&
            lhs.estimatedGasLimit == rhs.estimatedGasLimit &&
            lhs.customGasLimit == rhs.customGasLimit &&
            lhs.customByteFee == rhs.customByteFee &&
            lhs.sendMaxAmount == rhs.sendMaxAmount &&
            lhs.isStakingOperation == rhs.isStakingOperation &&
            lhs.transactionType == rhs.transactionType &&
            lhs.memoFunctionDictionary == rhs.memoFunctionDictionary &&
            lhs.wasmContractPayload == rhs.wasmContractPayload &&
            lhs.feeCoinSnapshot == rhs.feeCoinSnapshot &&
            lhs.cosmosStakingPayload == rhs.cosmosStakingPayload &&
            lhs.solanaStakingPayload == rhs.solanaStakingPayload
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(coinSnapshot)
        hasher.combine(vaultSnapshot)
        hasher.combine(fromAddress)
        hasher.combine(toAddress)
        hasher.combine(toAddressLabel)
        hasher.combine(amount)
        hasher.combine(amountInFiat)
        hasher.combine(memo)
        hasher.combine(destinationTag)
        hasher.combine(gas)
        hasher.combine(fee)
        hasher.combine(feeMode)
        hasher.combine(estimatedGasLimit)
        hasher.combine(customGasLimit)
        hasher.combine(customByteFee)
        hasher.combine(sendMaxAmount)
        hasher.combine(isStakingOperation)
        hasher.combine(transactionType)
        hasher.combine(memoFunctionDictionary)
        hasher.combine(wasmContractPayload)
        hasher.combine(feeCoinSnapshot)
        hasher.combine(cosmosStakingPayload)
        hasher.combine(solanaStakingPayload)
    }
}

extension SendTransaction {
    init(
        coin: Coin,
        vault: Vault,
        fromAddress: String,
        toAddress: String,
        toAddressLabel: String?,
        amount: String,
        amountInFiat: String,
        memo: String,
        destinationTag: UInt32? = nil,
        gas: BigInt,
        fee: BigInt,
        feeMode: FeeMode,
        estimatedGasLimit: BigInt?,
        customGasLimit: BigInt?,
        customByteFee: BigInt?,
        sendMaxAmount: Bool,
        isStakingOperation: Bool,
        transactionType: VSTransactionType,
        memoFunctionDictionary: [String: String],
        wasmContractPayload: WasmExecuteContractPayload?,
        feeCoin: Coin,
        cosmosStakingPayload: CosmosStakingPayload? = nil,
        solanaStakingPayload: SolanaStakingPayload? = nil
    ) {
        self.coin = coin
        self.vault = vault
        self.coinSnapshot = SendCoinSnapshot(coin: coin)
        self.vaultSnapshot = SendVaultSnapshot(vault: vault)
        self.fromAddress = fromAddress
        self.toAddress = toAddress
        self.toAddressLabel = toAddressLabel
        self.amount = amount
        self.amountInFiat = amountInFiat
        self.memo = memo
        self.destinationTag = destinationTag
        self.gas = gas
        self.fee = fee
        self.feeMode = feeMode
        self.estimatedGasLimit = estimatedGasLimit
        self.customGasLimit = customGasLimit
        self.customByteFee = customByteFee
        self.sendMaxAmount = sendMaxAmount
        self.isStakingOperation = isStakingOperation
        self.transactionType = transactionType
        self.memoFunctionDictionary = memoFunctionDictionary
        self.wasmContractPayload = wasmContractPayload
        self.feeCoin = feeCoin
        self.feeCoinSnapshot = SendCoinSnapshot(coin: feeCoin)
        self.cosmosStakingPayload = cosmosStakingPayload
        self.solanaStakingPayload = solanaStakingPayload
    }
}

// MARK: - Construction helpers

extension SendTransaction {
    /// Resolve the chain's native coin from the vault (or fall back to the
    /// source coin if the vault doesn't hold a native).
    static func resolveFeeCoin(coin: Coin, vault: Vault) -> Coin {
        guard !coin.isNativeToken else { return coin }
        return vault.coins.nativeCoin(chain: coin.chain) ?? coin
    }

    /// Default-fill an empty SendTransaction for a given coin/vault pair. Used
    /// as the seed for SendDetailsViewModel; real hand-off transactions are
    /// constructed by `SendDetailsViewModel.makeTransaction()` only when the
    /// user taps Continue.
    static func empty(coin: Coin, vault: Vault) -> SendTransaction {
        SendTransaction(
            coin: coin,
            vault: vault,
            fromAddress: coin.address,
            toAddress: "",
            toAddressLabel: nil,
            amount: "",
            amountInFiat: "",
            memo: "",
            gas: .zero,
            fee: .zero,
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: resolveFeeCoin(coin: coin, vault: vault)
        )
    }
}

// MARK: - Builder

extension SendTransaction {
    func copy(
        coin: Coin? = nil,
        vault: Vault? = nil,
        fromAddress: String? = nil,
        toAddress: String? = nil,
        toAddressLabel: SendTransactionUpdate<String?>? = nil,
        amount: String? = nil,
        amountInFiat: String? = nil,
        memo: String? = nil,
        destinationTag: SendTransactionUpdate<UInt32?>? = nil,
        gas: BigInt? = nil,
        fee: BigInt? = nil,
        feeMode: FeeMode? = nil,
        estimatedGasLimit: SendTransactionUpdate<BigInt?>? = nil,
        customGasLimit: SendTransactionUpdate<BigInt?>? = nil,
        customByteFee: SendTransactionUpdate<BigInt?>? = nil,
        sendMaxAmount: Bool? = nil,
        isStakingOperation: Bool? = nil,
        transactionType: VSTransactionType? = nil,
        memoFunctionDictionary: [String: String]? = nil,
        wasmContractPayload: SendTransactionUpdate<WasmExecuteContractPayload?>? = nil,
        feeCoin: Coin? = nil,
        cosmosStakingPayload: SendTransactionUpdate<CosmosStakingPayload?>? = nil,
        solanaStakingPayload: SendTransactionUpdate<SolanaStakingPayload?>? = nil
    ) -> SendTransaction {
        let resolvedVault = vault ?? self.vault
        let resolvedCoin = coin ?? self.coin
        let resolvedToAddressLabel: String? = {
            guard let toAddressLabel else { return self.toAddressLabel }
            return toAddressLabel.value
        }()
        let resolvedEstimatedGasLimit: BigInt? = {
            guard let estimatedGasLimit else { return self.estimatedGasLimit }
            return estimatedGasLimit.value
        }()
        let resolvedCustomGasLimit: BigInt? = {
            guard let customGasLimit else { return self.customGasLimit }
            return customGasLimit.value
        }()
        let resolvedCustomByteFee: BigInt? = {
            guard let customByteFee else { return self.customByteFee }
            return customByteFee.value
        }()
        let resolvedWasmContractPayload: WasmExecuteContractPayload? = {
            guard let wasmContractPayload else { return self.wasmContractPayload }
            return wasmContractPayload.value
        }()
        let resolvedCosmosStakingPayload: CosmosStakingPayload? = {
            guard let cosmosStakingPayload else { return self.cosmosStakingPayload }
            return cosmosStakingPayload.value
        }()
        let resolvedSolanaStakingPayload: SolanaStakingPayload? = {
            guard let solanaStakingPayload else { return self.solanaStakingPayload }
            return solanaStakingPayload.value
        }()
        let resolvedDestinationTag: UInt32? = {
            guard let destinationTag else { return self.destinationTag }
            return destinationTag.value
        }()
        return SendTransaction(
            coin: resolvedCoin,
            vault: resolvedVault,
            fromAddress: fromAddress ?? self.fromAddress,
            toAddress: toAddress ?? self.toAddress,
            toAddressLabel: resolvedToAddressLabel,
            amount: amount ?? self.amount,
            amountInFiat: amountInFiat ?? self.amountInFiat,
            memo: memo ?? self.memo,
            destinationTag: resolvedDestinationTag,
            gas: gas ?? self.gas,
            fee: fee ?? self.fee,
            feeMode: feeMode ?? self.feeMode,
            estimatedGasLimit: resolvedEstimatedGasLimit,
            customGasLimit: resolvedCustomGasLimit,
            customByteFee: resolvedCustomByteFee,
            sendMaxAmount: sendMaxAmount ?? self.sendMaxAmount,
            isStakingOperation: isStakingOperation ?? self.isStakingOperation,
            transactionType: transactionType ?? self.transactionType,
            memoFunctionDictionary: memoFunctionDictionary ?? self.memoFunctionDictionary,
            wasmContractPayload: resolvedWasmContractPayload,
            feeCoin: feeCoin ?? self.feeCoin,
            cosmosStakingPayload: resolvedCosmosStakingPayload,
            solanaStakingPayload: resolvedSolanaStakingPayload
        )
    }

    /// Builder for refresh paths in Verify — re-fetched chain-specific / fees
    /// produce a new SendTransaction with the same identity fields.
    ///
    /// `customGasLimit` and `customByteFee` are intentionally NOT clearable
    /// via this builder: if the caller wants to refresh fees but the user
    /// already pinned a custom gas, the pinned value sticks. That's the fix
    /// for the bug where Verify refresh dropped custom gas (decision 3).
    func with(
        toAddress: String? = nil,
        amount: String? = nil,
        gas: BigInt? = nil,
        fee: BigInt? = nil,
        feeMode: FeeMode? = nil,
        estimatedGasLimit: BigInt? = nil,
        memo: String? = nil,
        sendMaxAmount: Bool? = nil,
        isStakingOperation: Bool? = nil,
        memoFunctionDictionary: [String: String]? = nil,
        wasmContractPayload: WasmExecuteContractPayload? = nil
    ) -> SendTransaction {
        copy(
            toAddress: toAddress,
            amount: amount,
            memo: memo,
            gas: gas,
            fee: fee,
            feeMode: feeMode,
            estimatedGasLimit: estimatedGasLimit.map { .set($0) },
            sendMaxAmount: sendMaxAmount,
            isStakingOperation: isStakingOperation,
            memoFunctionDictionary: memoFunctionDictionary,
            wasmContractPayload: wasmContractPayload.map { .set($0) }
        )
    }
}

// MARK: - Convenience computed (delegates to SendCryptoLogic)

extension SendTransaction {
    var gasLimit: BigInt {
        customGasLimit ?? estimatedGasLimit ?? BigInt(defaultGasLimit)
    }

    private var defaultGasLimit: Int64 {
        coin.isNativeToken ? EVMHelper.defaultETHTransferGasUnit : EVMHelper.defaultERC20TransferGasUnit
    }

    var byteFee: BigInt {
        customByteFee ?? gas
    }

    var amountInRaw: BigInt {
        SendCryptoLogic.amountInRaw(coin: coin, amount: amount)
    }

    var amountDecimal: Decimal {
        SendCryptoLogic.amountDecimal(coin: coin, amount: amount)
    }

    var gasDecimal: Decimal {
        SendCryptoLogic.gasDecimal(gas: gas)
    }

    var isAmountExceeded: Bool {
        SendCryptoLogic.isAmountExceeded(
            coin: coin,
            amount: amount,
            sendMaxAmount: sendMaxAmount,
            fee: fee,
            gas: gas,
            isStakingOperation: isStakingOperation
        )
    }

    var canBeReaped: Bool {
        SendCryptoLogic.canBeReaped(coin: coin, amount: amount, gas: gas)
    }

    var isDeposit: Bool {
        SendCryptoLogic.isDeposit(coin: coin, memoFunctionDictionary: memoFunctionDictionary)
    }

    var gasInReadable: String {
        SendCryptoLogic.gasInReadable(coin: coin, gasNativeCoin: feeCoin, gas: gas, fee: fee)
    }
}
