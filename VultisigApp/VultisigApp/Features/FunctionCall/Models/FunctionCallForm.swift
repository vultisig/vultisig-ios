import Foundation
import OSLog
import SwiftUI
import VultisigCommonData

import UniformTypeIdentifiers
import WalletCore
import BigInt

/// Mutable form-state holder for the FunctionCall + Referral form layer.
///
/// **Role**: backs the user-facing form for FunctionCall (LP add, stake,
/// mint, cosmos merge/IBC/switch, secured-asset mint/withdraw, etc.) and
/// for the Referral flow. SwiftUI binds form fields directly to this class
/// via `@ObservedObject` / `@StateObject`. The 11 `FunctionCall*` sub-models
/// share state through it (token selection, amount, memo dict).
///
/// **Boundary**: at the navigation point (when the flow constructs a
/// `KeysignPayload` or navigates to `FunctionCallRoute.verify` /
/// `SendRoute.verify`), callers convert this mutable form-state into the
/// immutable `SendTransaction` struct via
/// `SendTransaction.fromFunctionCallForm(_:vault:)`. Everything downstream
/// of the boundary runs on the new immutable shape.
///
/// **Why it exists**: the FunctionCall form's complexity (per-coin token
/// dropdowns that mutate the shared coin, cross-sub-model state sharing)
/// genuinely benefits from a single mutable reference type. The simpler
/// Send / TRON / Circle flows construct `SendTransaction` directly at
/// hand-off and don't need this class.
class FunctionCallForm: ObservableObject, Hashable {
    @Published var fromAddress: String = ""
    @Published var toAddress: String = .empty
    @Published var toAddressLabel: String? = nil
    // Internal tracking for ENS/TNS resolution - prevents stale label on re-validation
    var lastResolvedAddress: String? = nil
    @Published var amount: String = .empty
    @Published var amountInFiat: String = .empty
    @Published var memo: String = .empty
    @Published var gas: BigInt = .zero
    @Published var estematedGasLimit: BigInt?
    @Published var customGasLimit: BigInt?
    @Published var customByteFee: BigInt?
    @Published var fee: BigInt = .zero
    @Published var isCalculatingFee: Bool = false
    @Published var feeMode: FeeMode = .default
    @Published var sendMaxAmount: Bool = false
    @Published var fastVaultPassword: String = .empty
    @Published var isStakingOperation: Bool = false
    @Published var memoFunctionDictionary: ThreadSafeDictionary<String, String> = ThreadSafeDictionary()
    var wasmContractPayload: WasmExecuteContractPayload?

    @Published var coin: Coin = .example
    @Published var transactionType: VSTransactionType = .unspecified
    @Published var vault: Vault?
    @Published var pendingRetryReason: BroadcastRetryReason?

    var txVault: Vault? { vault ?? AppViewModel.shared.selectedVault }

    var gasLimit: BigInt {
        let defaultGasLimit = coin.isNativeToken
            ? EVMHelper.defaultETHTransferGasUnit
            : EVMHelper.defaultERC20TransferGasUnit
        return customGasLimit ?? estematedGasLimit ?? BigInt(defaultGasLimit)
    }

    var byteFee: BigInt {
        return customByteFee ?? gas
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

    var isDeposit: Bool {
        SendCryptoLogic.isDeposit(coin: coin, memoFunctionDictionary: memoFunctionDictionary.allItems())
    }

    var canBeReaped: Bool {
        SendCryptoLogic.canBeReaped(coin: coin, amount: amount, gas: gas)
    }

    func hasEnoughNativeTokensToPayTheFees(specific: BlockChainSpecific) async -> (Bool, String) {
        var errorMessage = ""
        guard !coin.isNativeToken else { return (true, errorMessage) }

        if let vault = txVault {
            if let nativeToken = vault.coins.nativeCoin(chain: coin.chain) {
                await BalanceService.shared.updateBalance(for: nativeToken)

                let nativeTokenBalance = nativeToken.rawBalance.toBigInt()

                if specific.fee > nativeTokenBalance {
                    errorMessage = String(format: "insufficientGasTokenError".localized, nativeToken.ticker, coin.ticker)

                    return (false, errorMessage)
                }
                return (true, errorMessage)
            } else {
                errorMessage = String(format: "noGasTokenFoundError".localized, coin.chain.name)
                return (false, errorMessage)
            }
        }
        errorMessage = "unableToVerifyGasTokenError".localized
        return (false, errorMessage)
    }

    func getNativeTokenBalance() async -> String {
        guard !coin.isNativeToken else { return .zero }

        if let vault = txVault {
            if let nativeToken = vault.coins.nativeCoin(chain: coin.chain) {
                await BalanceService.shared.updateBalance(for: nativeToken)
                let nativeTokenRawBalance = Decimal(string: nativeToken.rawBalance) ?? .zero

                let nativeDecimals = nativeToken.decimals

                let nativeTokenBalance = nativeTokenRawBalance / pow(10, nativeDecimals)

                let nativeTokenBalanceDecimal = nativeTokenBalance.formatForDisplay(maxDecimals: 8)

                return "\(nativeTokenBalanceDecimal) \(nativeToken.ticker)"
            } else {
                print("No native token found for chain \(coin.chain.name)")
                return .zero
            }
        }
        print("Failed to access current vault")
        return .zero
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

    var gasInReadable: String {
        let resolvedNative: Coin = {
            guard !coin.isNativeToken,
                  let vault = txVault,
                  let nativeToken = vault.coins.nativeCoin(chain: coin.chain)
            else { return coin }
            return nativeToken
        }()
        return SendCryptoLogic.gasInReadable(coin: coin, gasNativeCoin: resolvedNative, gas: gas, fee: fee)
    }

    init() { }

    init(coin: Coin) {
        self.reset(coin: coin)
    }

    static func == (lhs: FunctionCallForm, rhs: FunctionCallForm) -> Bool {
        lhs.fromAddress == rhs.fromAddress &&
        lhs.toAddress == rhs.toAddress &&
        lhs.amount == rhs.amount &&
        lhs.memo == rhs.memo &&
        lhs.gas == rhs.gas &&
        lhs.sendMaxAmount == rhs.sendMaxAmount
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(fromAddress)
        hasher.combine(toAddress)
        hasher.combine(amount)
        hasher.combine(memo)
        hasher.combine(gas)
        hasher.combine(sendMaxAmount)
    }

    func reset(coin: Coin) {
        self.toAddress = .empty
        self.toAddressLabel = nil
        self.lastResolvedAddress = nil
        self.amount = .empty
        self.amountInFiat = .empty
        self.memo = .empty
        self.gas = .zero
        self.fee = .zero  // Clear previous fee
        self.isCalculatingFee = false  // Reset UI state
        self.estematedGasLimit = nil
        self.customGasLimit = nil
        self.customByteFee = nil
        self.feeMode = .default
        self.coin = coin
        self.sendMaxAmount = false
        self.fromAddress = coin.address
        self.wasmContractPayload = nil  // Clear contract payload
        self.transactionType = .unspecified  // Reset transaction type
        self.memoFunctionDictionary = ThreadSafeDictionary()  // Clear memo functions
        self.fastVaultPassword = .empty  // Clear password state
        self.isStakingOperation = false // Reset staking operation flag
    }

    func parseCryptoURI(_ uri: String) {
        guard URLComponents(string: uri) != nil else {
            print("Invalid URI")
            return
        }

        let (address, amount, message) = Utils.parseCryptoURI(uri)

        self.toAddress = address
        self.toAddressLabel = nil
        self.amount = amount
        self.memo = message
    }
}
