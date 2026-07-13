//
//  ThorchainRouterDepositBuilder.swift
//  VultisigApp
//
//  Shared builder for THORChain router deposits (LP adds and SECURE+ mints).
//  The router-deposit shim synthesis is extracted from
//  `FunctionCallVerifyViewModel` so the inline swap same-underlying path
//  (native/ERC20 L1 asset → its own secured form) reuses the exact same
//  deposit-payload construction instead of re-implementing it — the coupling
//  mitigation the #4788 plan calls out.
//

import BigInt
import Foundation

enum ThorchainRouterDepositBuilder {

    /// Synthesizes the router-deposit shim (`SwapPayload` + `ERC20ApprovePayload`)
    /// for a THORChain router deposit — LP adds and SECURE+ mints. ERC20 deposits
    /// ride the legacy swap-signing path: `EVMHelper.getSwapPreSignedInputData`
    /// needs a `THORChainSwapPayload` to build the router's `depositWithExpiry`
    /// call (which carries the memo to THORChain), so we synthesize one. The
    /// router routes by memo, so the same shim works for both LP adds and mints.
    /// Native sources and non-approve deposits need no shim → returns `(nil, nil)`.
    ///
    /// Extracted verbatim from `FunctionCallVerifyViewModel.createKeysignPayload`
    /// so both the Function-Call verify path and the inline swap SECURE+ path
    /// build the identical shim.
    @MainActor
    static func synthesizeRouterDeposit(
        tx: SendTransaction
    ) async throws -> (swapPayload: SwapPayload?, approvePayload: ERC20ApprovePayload?) {
        let isLPAdd = tx.memoFunctionDictionary["pool"] != nil
        let isSecuredAssetMint = tx.memo.hasPrefix("SECURE+")
        let isRouterDeposit = isLPAdd || isSecuredAssetMint
        guard isRouterDeposit, tx.coin.shouldApprove, !tx.toAddress.isEmpty else {
            return (nil, nil)
        }

        let inboundAddresses = await ThorchainService.shared.fetchThorchainInboundAddress()
        let chainName = ThorchainService.getInboundChainName(for: tx.coin.chain)
        guard let inbound = inboundAddresses.first(where: { $0.chain.uppercased() == chainName.uppercased() }) else {
            throw HelperError.runtimeError("Failed to find inbound address for \(chainName)")
        }

        let expirationTime = Date().addingTimeInterval(60 * 15)
        let thorchainSwapPayload = THORChainSwapPayload(
            fromAddress: tx.fromAddress,
            fromCoin: tx.coin,
            toCoin: tx.coin,
            vaultAddress: inbound.address,
            routerAddress: inbound.router,
            fromAmount: tx.amountInRaw,
            toAmountDecimal: tx.coin.decimal(for: tx.amountInRaw),
            toAmountLimit: "",
            streamingInterval: "",
            streamingQuantity: "",
            expirationTime: UInt64(expirationTime.timeIntervalSince1970),
            isAffiliate: false
        )
        let swapPayload: SwapPayload = tx.coin.chain == .mayaChain
            ? .mayachain(thorchainSwapPayload)
            : .thorchain(thorchainSwapPayload)
        let approvePayload = ERC20ApprovePayload(amount: tx.amountInRaw, spender: tx.toAddress)
        return (swapPayload, approvePayload)
    }

    /// Builds the SECURE+ mint DEPOSIT keysign payload for the inline swap
    /// same-underlying path: send `amount` of `fromCoin` to the THORChain inbound
    /// vault (native) / ERC20 router (approve sources) with memo
    /// `SECURE+:<vault thor address>`, which mints the secured form on settle. No
    /// new keysign/tx type — reuses `buildTransfer` + the shared shim above.
    @MainActor
    static func buildSecuredMintPayload(
        fromCoin: Coin,
        amount: Decimal,
        vault: Vault,
        blockChainService: BlockChainService = .shared,
        thorchainService: ThorchainService = .shared
    ) async throws -> KeysignPayload {
        guard let thorCoin = vault.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken }) else {
            throw HelperError.runtimeError("thorAddressNotFound".localized)
        }
        let thorAddress = thorCoin.address
        let toAddress = try await resolveInboundDestination(coin: fromCoin, thorchainService: thorchainService)

        let memo = "SECURE+:\(thorAddress)"
        let tx = SendTransaction.empty(coin: fromCoin, vault: vault).copy(
            toAddress: toAddress,
            amount: amount.formatToDecimal(digits: fromCoin.decimals),
            memo: memo,
            transactionType: .unspecified,
            memoFunctionDictionary: [
                "operation": "mint",
                "memo": memo,
                "amount": amount.description,
                "thorAddress": thorAddress
            ],
            wasmContractPayload: .set(nil)
        )

        let chainSpecific = try await blockChainService.fetchSpecific(tx: tx)
        let (swapPayload, approvePayload) = try await synthesizeRouterDeposit(tx: tx)
        return try await KeysignPayloadFactory().buildTransfer(
            coin: fromCoin,
            toAddress: toAddress,
            amount: tx.amountInRaw,
            memo: memo,
            chainSpecific: chainSpecific,
            swapPayload: swapPayload,
            approvePayload: approvePayload,
            vault: vault
        )
    }

    /// Resolves the L1 deposit destination for a SECURE+ mint: the THORChain
    /// inbound vault (native sources) or the ERC20 router (approve sources).
    /// Throws on a halted/paused or missing inbound so a mint never signs to an
    /// empty/stranded destination. Mirrors
    /// `FunctionCallSecuredAsset.fetchInboundAddressAndSetupApproval`.
    @MainActor
    static func resolveInboundDestination(
        coin: Coin,
        thorchainService: ThorchainService = .shared
    ) async throws -> String {
        if coin.chain == .thorChain {
            return coin.address
        }

        let addresses = await thorchainService.fetchThorchainInboundAddress()
        let chainName = ThorchainService.getInboundChainName(for: coin.chain)
        guard let inbound = addresses.first(where: { $0.chain.uppercased() == chainName.uppercased() }) else {
            throw HelperError.runtimeError(String(format: "inboundAddressNotFound".localized, chainName))
        }
        if inbound.halted || inbound.global_trading_paused ?? false || inbound.chain_trading_paused ?? false || inbound.chain_lp_actions_paused ?? false {
            throw HelperError.runtimeError(String(format: "inboundPaused".localized, inbound.chain))
        }

        if coin.shouldApprove {
            guard let router = inbound.router, !router.isEmpty else {
                throw HelperError.runtimeError(String(format: "routerNotAvailable".localized, inbound.chain))
            }
            return router
        }
        return inbound.address
    }
}
