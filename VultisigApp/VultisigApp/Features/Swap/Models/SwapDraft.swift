//
//  SwapDraft.swift
//  VultisigApp
//
//  Pure value-type mirror of `SwapTransaction`. Replaces the `ObservableObject`
//  class as the canonical form state once the swap pilot completes — see
//  [[projects/vultisig/transaction-model-refactor/spec/proposal]]. During the
//  transition (§1–§4) the bidirectional adapter in `SwapDraft+Adapter.swift`
//  keeps both representations in sync. Both the legacy class and the adapter
//  are deleted in §5.
//

import BigInt
import Foundation

struct SwapDraft: Equatable {
    var fromAmount: String = .empty
    var thorchainFee: BigInt = .zero
    var gas: BigInt = .zero
    var vultDiscountBps: Int = 0
    var referralDiscountBps: Int = 0
    var quote: SwapQuote?
    var isFastVault: Bool = false
    var fastVaultPassword: String = .empty
    var pendingRetryReason: BroadcastRetryReason?

    var fromCoin: Coin = .example
    var toCoin: Coin = .example
    var fromCoins: [Coin] = []
    var toCoins: [Coin] = []
}
