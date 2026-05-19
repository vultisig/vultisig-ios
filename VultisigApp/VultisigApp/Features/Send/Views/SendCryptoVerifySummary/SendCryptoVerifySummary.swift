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
    let decodedFunctionSignature: String?
    let decodedFunctionArguments: String?
    let memoFunctionDictionary: [String: String]?
    let feeCrypto: String
    let feeFiat: String
    let isCalculatingFee: Bool
    let coinImage: String
    let amount: String
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

    init(
        fromName: String,
        fromAddress: String,
        toAddress: String,
        toAlias: String? = nil,
        network: String,
        networkImage: String,
        memo: String,
        // Only for Function Calls
        decodedFunctionSignature: String? = nil,
        decodedFunctionArguments: String? = nil,
        memoFunctionDictionary: [String: String]? = nil,
        feeCrypto: String,
        feeFiat: String,
        isCalculatingFee: Bool = false,
        coinImage: String,
        amount: String,
        coinTicker: String,
        keysignPayload: KeysignPayload? = nil,
        hero: HeroContent? = nil,
        tokenDisplay: String? = nil,
        tokenDisplayIsUnlimited: Bool = false,
        vault: Vault? = nil,
        dappMetadata: DAppMetadata? = nil
    ) {
        self.fromName = fromName
        self.fromAddress = fromAddress
        self.toAddress = toAddress
        self.toAlias = toAlias
        self.network = network
        self.networkImage = networkImage
        self.memo = memo
        self.decodedFunctionSignature = decodedFunctionSignature
        self.decodedFunctionArguments = decodedFunctionArguments
        self.memoFunctionDictionary = memoFunctionDictionary
        self.feeCrypto = feeCrypto
        self.feeFiat = feeFiat
        self.isCalculatingFee = isCalculatingFee
        self.coinImage = coinImage
        self.amount = amount
        self.coinTicker = coinTicker
        self.keysignPayload = keysignPayload
        self.hero = hero
        self.tokenDisplay = tokenDisplay
        self.tokenDisplayIsUnlimited = tokenDisplayIsUnlimited
        self.vault = vault
        self.dappMetadata = dappMetadata
    }
}
