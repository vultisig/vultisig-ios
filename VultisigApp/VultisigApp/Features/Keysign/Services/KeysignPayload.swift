//
//  KeysignPayload.swift
//  VultisigApp
//

import Foundation
import BigInt

struct KeysignPayload: Codable, Hashable {
    let coin: Coin
    let toAddress: String
    let toAmount: BigInt
    let chainSpecific: BlockChainSpecific
    let utxos: [UtxoInfo]
    let memo: String?
    let swapPayload: SwapPayload?
    let approvePayload: ERC20ApprovePayload?
    let vaultPubKeyECDSA: String
    let vaultLocalPartyID: String
    let libType: String
    let wasmExecuteContractPayload: WasmExecuteContractPayload?
    let tronTransferContractPayload: TronTransferContractPayload?
    let tronTriggerSmartContractPayload: TronTriggerSmartContractPayload?
    let tronTransferAssetContractPayload: TronTransferAssetContractPayload?
    /// Set on the initiating device when constructing a QBTC claim. Local-only:
    /// not round-tripped through the proto `KeysignPayload`. See
    /// `QBTCClaimPayload` for rationale.
    let qbtcClaimPayload: QBTCClaimPayload?
    /// Marker round-tripped through the proto: signals to the peer device
    /// that the BTC ECDSA signature it's about to produce is for a QBTC
    /// claim. The peer derives the claimer's QBTC address from its own
    /// vault (same SecureVault → same QBTC coin → same derived address)
    /// and computes the message hash locally, refusing to blind-sign
    /// whatever the initiator asks for.
    let isQbtcClaim: Bool
    let skipBroadcast: Bool
    let signData: SignData?
    let dappMetadata: DAppMetadata?

    /// Memberwise init with `dappMetadata` defaulting to `nil` so existing
    /// construction sites don't need to opt into the new field. The proto
    /// mapping is the only producer of non-nil dApp metadata today.
    init(
        coin: Coin,
        toAddress: String,
        toAmount: BigInt,
        chainSpecific: BlockChainSpecific,
        utxos: [UtxoInfo],
        memo: String?,
        swapPayload: SwapPayload?,
        approvePayload: ERC20ApprovePayload?,
        vaultPubKeyECDSA: String,
        vaultLocalPartyID: String,
        libType: String,
        wasmExecuteContractPayload: WasmExecuteContractPayload?,
        tronTransferContractPayload: TronTransferContractPayload?,
        tronTriggerSmartContractPayload: TronTriggerSmartContractPayload?,
        tronTransferAssetContractPayload: TronTransferAssetContractPayload?,
        qbtcClaimPayload: QBTCClaimPayload?,
        isQbtcClaim: Bool,
        skipBroadcast: Bool,
        signData: SignData?,
        dappMetadata: DAppMetadata? = nil
    ) {
        self.coin = coin
        self.toAddress = toAddress
        self.toAmount = toAmount
        self.chainSpecific = chainSpecific
        self.utxos = utxos
        self.memo = memo
        self.swapPayload = swapPayload
        self.approvePayload = approvePayload
        self.vaultPubKeyECDSA = vaultPubKeyECDSA
        self.vaultLocalPartyID = vaultLocalPartyID
        self.libType = libType
        self.wasmExecuteContractPayload = wasmExecuteContractPayload
        self.tronTransferContractPayload = tronTransferContractPayload
        self.tronTriggerSmartContractPayload = tronTriggerSmartContractPayload
        self.tronTransferAssetContractPayload = tronTransferAssetContractPayload
        self.qbtcClaimPayload = qbtcClaimPayload
        self.isQbtcClaim = isQbtcClaim
        self.skipBroadcast = skipBroadcast
        self.signData = signData
        self.dappMetadata = dappMetadata
    }

    /// Returns a copy of the payload with `signData` swapped. Used by the
    /// Cosmos staking branch in Verify-time keysign-payload assembly so a
    /// payload built without a SignDoc (the default `buildTransfer` shape)
    /// can be re-emitted carrying the proto-encoded staking msg without
    /// duplicating the 18-field memberwise init at every call site.
    func withSignData(_ signData: SignData) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: toAddress,
            toAmount: toAmount,
            chainSpecific: chainSpecific,
            utxos: utxos,
            memo: memo,
            swapPayload: swapPayload,
            approvePayload: approvePayload,
            vaultPubKeyECDSA: vaultPubKeyECDSA,
            vaultLocalPartyID: vaultLocalPartyID,
            libType: libType,
            wasmExecuteContractPayload: wasmExecuteContractPayload,
            tronTransferContractPayload: tronTransferContractPayload,
            tronTriggerSmartContractPayload: tronTriggerSmartContractPayload,
            tronTransferAssetContractPayload: tronTransferAssetContractPayload,
            qbtcClaimPayload: qbtcClaimPayload,
            isQbtcClaim: isQbtcClaim,
            skipBroadcast: skipBroadcast,
            signData: signData,
            dappMetadata: dappMetadata
        )
    }

    var signAmino: SignAmino? {
        guard case let .signAmino(amino) = signData else {
            return nil
        }
        return amino
    }

    var signDirect: SignDirect? {
        guard case let .signDirect(direct) = signData else {
            return nil
        }
        return direct
    }

    var signSolana: SignSolana? {
        guard case let .signSolana(solana) = signData else {
            return nil
        }
        return solana
    }

    var signBitcoin: SignBitcoin? {
        guard case let .signBitcoin(bitcoin) = signData else {
            return nil
        }
        return bitcoin
    }

    var signTon: SignTon? {
        guard case let .signTon(ton) = signData else {
            return nil
        }
        return ton
    }

    var signSui: SignSui? {
        guard case let .signSui(sui) = signData else {
            return nil
        }
        return sui
    }

    var fromAmountString: String {
        let decimalAmount = Decimal(string: swapPayload?.fromAmount.description ?? "") ?? Decimal.zero
        let power = Decimal(sign: .plus, exponent: -(swapPayload?.fromCoin.decimals ?? 1), significand: 1)
        return "\((decimalAmount * power).formatForDisplay()) \(swapPayload?.fromCoin.ticker ?? "")"
    }

    var fromAmountFiatString: String {
        let newValueFiat = (Decimal(string: swapPayload?.fromAmount.description ?? "") ?? Decimal.zero) * Decimal(swapPayload?.fromCoin.price ?? 1)
        let truncatedValueFiat = newValueFiat.truncated(toPlaces: 2)
        let power = Decimal(sign: .plus, exponent: -(swapPayload?.fromCoin.decimals ?? 1), significand: 1)
        return NSDecimalNumber(decimal: truncatedValueFiat * power).stringValue
    }

    var toAmountWithTickerString: String {
        return "\(toAmountString) \(coin.ticker)"
    }

    var toAmountDecimal: Decimal {
        let decimalAmount = Decimal(string: toAmount.description) ?? Decimal.zero
        let power = Decimal(sign: .plus, exponent: -coin.decimals, significand: 1)
        return decimalAmount * power
    }

    var toAmountString: String {
        return toAmountDecimal.formatForDisplay()
    }

    var toSwapAmountFiatString: String {
        swapPayload?.toCoin.fiat(decimal: swapPayload?.toAmountDecimal ?? 0).description ?? ""
    }

    var toSendAmountFiatString: String {
        return coin.fiat(decimal: toAmountDecimal).description
    }

    /// Returns the dApp-supplied fee amount (in base units) for Cosmos-based chains,
    /// extracted from `signAmino.fee.amount`. Returns `nil` when no dApp signData is
    /// present or the chain isn't Cosmos-rooted, letting callers fall back to the
    /// estimated `blockChainSpecific` fee.
    ///
    /// Fixes: Rujira CosmWasm calls declare `fee.amount = 0` but the estimate shows
    /// a non-zero fallback (e.g. 0.02 RUNE). Parity with Windows PR #3843.
    func dappSuppliedCosmosFee() -> UInt64? {
        guard coin.chainType == .Cosmos || coin.chainType == .THORChain else {
            return nil
        }

        // signAmino path: fee is directly accessible.
        // Filter by the chain's native fee denom to avoid mixing denominations
        // (e.g. native token + IBC token fees summed together).
        if let amino = signAmino {
            let nativeDenom = coin.chain.feeUnit.lowercased()
            let denomMatched = amino.fee.amount
                .filter { $0.denom.lowercased() == nativeDenom }
                .compactMap { UInt64($0.amount) }
            if !denomMatched.isEmpty {
                return denomMatched.reduce(0, +)
            }
            return nil
        }

        // signDirect would require protobuf decoding of authInfoBytes — skip for now.
        // Rujira CosmWasm uses signAmino as the primary signing path.
        return nil
    }

    static let example = KeysignPayload(
        coin: Coin.example,
        toAddress: "toAddress",
        toAmount: 100,
        chainSpecific: BlockChainSpecific.UTXO(byteFee: 100, sendMaxAmount: false),
        utxos: [],
        memo: "Memo",
        swapPayload: nil,
        approvePayload: nil,
        vaultPubKeyECDSA: "12345",
        vaultLocalPartyID: "iPhone-100",
        libType: LibType.DKLS.toString(),
        wasmExecuteContractPayload: nil,
        tronTransferContractPayload: nil,
        tronTriggerSmartContractPayload: nil,
        tronTransferAssetContractPayload: nil,
        qbtcClaimPayload: nil,
        isQbtcClaim: false,
        skipBroadcast: false,
        signData: nil,
        dappMetadata: nil
    )
}
