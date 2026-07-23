//
//  SendCryptoVerifySummary.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/07/2025.
//

struct SendCryptoVerifySummary {
    let fromName: String
    let fromAddress: String
    let toAddress: String
    let toAlias: String?
    let network: String
    let networkImage: String
    let memo: String
    /// XRP destination tag, pre-formatted for display. Rendered as its own
    /// row under the memo. `nil` (the default) hides the row.
    let destinationTag: String?
    let decodedFunctionSignature: String?
    let decodedFunctionArguments: String?
    let memoFunctionDictionary: [String: String]?
    let feeCrypto: String
    let feeFiat: String
    let isCalculatingFee: Bool
    let coinImage: String
    let amount: String
    /// Pre-formatted fiat value of `amount` (e.g. "$12.34"), rendered as a
    /// sub-line under the amount in the non-hero send header. Empty when the
    /// amount doesn't map to a single priced coin transfer (swap / contract
    /// call / LP) or when no price is available. Defaults to empty so existing
    /// construction sites are unaffected.
    let amountFiat: String
    let coinTicker: String
    let keysignPayload: KeysignPayload?
    let hero: HeroContent?
    /// Resolved token display for EVM contract calls, e.g. "0.3 USDC" or "Unlimited USDC".
    let tokenDisplay: String?
    /// True when `tokenDisplay` is the "Unlimited" sentinel for an approval —
    /// the render should highlight it with a warning icon and warning color.
    let tokenDisplayIsUnlimited: Bool
    /// Active vault — required so TonConnect signing can resolve enabled
    /// jettons against the user's coin list. `nil` for non-TonConnect paths.
    let vault: Vault?
    /// dApp identity attached to the keysign request (set by remote-pair flows).
    /// When non-nil, the verify view renders a `DAppRequestBanner` above the
    /// hero so signers can sanity-check who originated the transaction.
    let dappMetadata: DAppMetadata?
    /// Extra label/value rows, rendered inside the summary card beneath the
    /// network-fee row.
    ///
    /// For a cost the transaction really carries but that the fee row cannot
    /// express — the first is a limit-order cancel's attached dust, which
    /// THORChain donates to the pool with no refund path. That belongs among the
    /// costs, not in a red alert block below them: it is a normal, disclosed
    /// part of the transaction, and styling it as an alarm made a real charge
    /// read as a warning about something going wrong.
    ///
    /// Empty by default, so no existing construction site changes.
    let additionalRows: [SendCryptoVerifySummaryRow]

    init(
        fromName: String,
        fromAddress: String,
        toAddress: String,
        toAlias: String? = nil,
        network: String,
        networkImage: String,
        memo: String,
        destinationTag: String? = nil,
        // Only for Function Calls
        decodedFunctionSignature: String? = nil,
        decodedFunctionArguments: String? = nil,
        memoFunctionDictionary: [String: String]? = nil,
        feeCrypto: String,
        feeFiat: String,
        isCalculatingFee: Bool = false,
        coinImage: String,
        amount: String,
        amountFiat: String = "",
        coinTicker: String,
        keysignPayload: KeysignPayload? = nil,
        hero: HeroContent? = nil,
        tokenDisplay: String? = nil,
        tokenDisplayIsUnlimited: Bool = false,
        vault: Vault? = nil,
        dappMetadata: DAppMetadata? = nil,
        additionalRows: [SendCryptoVerifySummaryRow] = []
    ) {
        self.fromName = fromName
        self.fromAddress = fromAddress
        self.toAddress = toAddress
        self.toAlias = toAlias
        self.network = network
        self.networkImage = networkImage
        self.memo = memo
        self.destinationTag = destinationTag
        self.decodedFunctionSignature = decodedFunctionSignature
        self.decodedFunctionArguments = decodedFunctionArguments
        self.memoFunctionDictionary = memoFunctionDictionary
        self.feeCrypto = feeCrypto
        self.feeFiat = feeFiat
        self.isCalculatingFee = isCalculatingFee
        self.coinImage = coinImage
        self.amount = amount
        self.amountFiat = amountFiat
        self.coinTicker = coinTicker
        self.keysignPayload = keysignPayload
        self.hero = hero
        self.tokenDisplay = tokenDisplay
        self.tokenDisplayIsUnlimited = tokenDisplayIsUnlimited
        self.vault = vault
        self.dappMetadata = dappMetadata
        self.additionalRows = additionalRows
    }
}

/// One extra label/value row for the verify summary card.
///
/// `title` is a LOCALIZATION KEY — `getValueCell` localizes it, like every other
/// row's title. `value` is already formatted for display.
struct SendCryptoVerifySummaryRow: Identifiable {
    let title: String
    let value: String

    var id: String { title }
}
