//
//  TransactionDonePayload.swift
//  VultisigApp
//
//  Value-type payload consumed by `TransactionDoneView` (the unified
//  post-keysign "done" surface used by Send, Swap, QBTC claim, and the
//  keysign-cosigner path). Each upstream flow constructs one in its
//  route builder and hands it to the view; the view itself is
//  flow-agnostic.
//
//  Mirrors Android's `TxDoneScaffold` slot-API by separating the
//  flow-shared concerns (hash row, status header, "Done" CTA, history
//  recording) from the flow-specific token + detail composition.
//

struct FeeDisplay: Hashable {
    let crypto: String
    let fiat: String
}

struct TransactionDonePayload: Hashable {
    let coin: Coin
    let amountCrypto: String
    let amountFiat: String
    var hero: HeroContent? = nil
    let hash: String
    let explorerLink: String
    let memo: String
    let isSend: Bool

    let fromAddress: String
    let toAddress: String
    var toAlias: String? = nil
    let fee: FeeDisplay
    let keysignPayload: KeysignPayload?
    let pubKeyECDSA: String
    /// Verb used by the status header so QBTC claim renders the same surface
    /// with "Claim" copy instead of "Transaction" copy. Default `.send`
    /// preserves every existing caller's behavior.
    var verb: TransactionActionVerb = .send
    /// Forwarded into the header so the dApp request banner can render
    /// above the hero on the done screen (cosigner dApp signing path).
    var dappMetadata: DAppMetadata? = nil
}
