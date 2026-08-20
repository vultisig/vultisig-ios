//
//  HeroContent.swift
//  VultisigApp
//

import Foundation

/// Content for the signing hero. Cases distinguish title-only, committed balance
/// changes, swaps, and projected settlement amounts.
enum HeroContent: Hashable {
    case title(text: String, caption: String?)
    case send(title: String?, coin: HeroCoinAmount)
    case receive(title: String?, coin: HeroCoinAmount)
    case swap(title: String?, from: HeroCoinAmount, to: HeroCoinAmount)

    /// A settlement estimate paired with the scope the transaction commits to.
    /// It is distinct from `.send` so estimates cannot look committed; callers
    /// must separately disclose any signed carrier amount this hero replaces.
    case projected(title: String, estimate: HeroCoinAmount?, scope: String)

    /// Replaces only the verb, preserving richer figures. `nil` is inert.
    func retitled(_ title: String?) -> HeroContent {
        guard let title else { return self }
        switch self {
        case .title(_, let caption): return .title(text: title, caption: caption)
        case .send(_, let coin): return .send(title: title, coin: coin)
        case .receive(_, let coin): return .receive(title: title, coin: coin)
        case .swap(_, let from, let to): return .swap(title: title, from: from, to: to)
        case .projected(_, let estimate, let scope):
            return .projected(title: title, estimate: estimate, scope: scope)
        }
    }

    var title: String? {
        switch self {
        case .title(let text, _): return text
        case .send(let title, _): return title
        case .receive(let title, _): return title
        case .swap(let title, _, _): return title
        case .projected(let title, _, _): return title
        }
    }

    /// Reprices only amounts that retained a trusted local pricing source.
    /// Verify calls this again when the rate cache changes; no chain read is
    /// repeated and peer-supplied display metadata never becomes authoritative.
    func refreshedFiat() -> HeroContent {
        switch self {
        case .title:
            return self
        case .send(let title, let coin):
            return .send(title: title, coin: coin.refreshedFiat())
        case .receive(let title, let coin):
            return .receive(title: title, coin: coin.refreshedFiat())
        case .swap(let title, let from, let to):
            return .swap(title: title, from: from.refreshedFiat(), to: to.refreshedFiat())
        case .projected(let title, let estimate, let scope):
            return .projected(title: title, estimate: estimate?.refreshedFiat(), scope: scope)
        }
    }
}

struct HeroCoinAmount: Hashable {
    private struct FiatSource: Hashable {
        let amount: Decimal
        let coin: CoinMeta
    }

    let amount: String
    let ticker: String
    let logo: String
    /// Pre-formatted fiat value of `amount` (e.g. "$12.34"), rendered as a
    /// sub-line under the amount. `nil` when no price is resolvable, or for
    /// callers that intentionally omit fiat.
    let fiat: String?
    private let fiatSource: FiatSource?

    init(amount: String, ticker: String, logo: String, fiat: String? = nil) {
        self.amount = amount
        self.ticker = ticker
        self.logo = logo
        self.fiat = fiat
        self.fiatSource = nil
    }

    /// Builds a display amount from a trusted local coin and keeps enough
    /// source data to reprice it if rates arrive after Verify's first frame.
    init(amount: Decimal, coin: Coin) {
        self.init(amount: amount, coin: coin.toCoinMeta())
    }

    /// Curated metadata is used for chain-native and denom amounts whose
    /// display asset is derived from signed units rather than a payload coin.
    init(amount: Decimal, coin: CoinMeta) {
        let fiat = CryptoAmountFormatter.amountInFiat(coin: coin, amount: amount)
        self.amount = amount.formatToDecimal(digits: coin.decimals)
        self.ticker = coin.ticker
        self.logo = coin.logo
        self.fiat = fiat.isEmpty ? nil : fiat
        self.fiatSource = FiatSource(amount: amount, coin: coin)
    }

    func refreshedFiat() -> HeroCoinAmount {
        guard let source = fiatSource else { return self }
        let fiat = CryptoAmountFormatter.amountInFiat(coin: source.coin, amount: source.amount)
        return HeroCoinAmount(
            amount: amount,
            ticker: ticker,
            logo: logo,
            fiat: fiat.isEmpty ? nil : fiat,
            fiatSource: source
        )
    }

    private init(
        amount: String,
        ticker: String,
        logo: String,
        fiat: String?,
        fiatSource: FiatSource
    ) {
        self.amount = amount
        self.ticker = ticker
        self.logo = logo
        self.fiat = fiat
        self.fiatSource = fiatSource
    }
}
