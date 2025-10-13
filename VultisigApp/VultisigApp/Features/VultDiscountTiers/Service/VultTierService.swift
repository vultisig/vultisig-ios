//
//  VultBalanceService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/10/2025.
//

import BigInt

struct VultTierService {
    let vultTicker = "VULT"
    
    func fetchDiscountTier(for vault: Vault) async -> VultDiscountTier? {
        let balance = await fetchVultBalance(for: vault)
        return VultDiscountTier.allCases
            .sorted { $0.balanceToUnlock > $1.balanceToUnlock }
            .first { balance >= $0.balanceToUnlock }
    }
}

private extension VultTierService {
    func fetchVultBalance(for vault: Vault) async -> BigInt {
        await addEthChainIfNeeded(for: vault)
        let vultToken = await getOrAddVultTokenIfNeeded(to: vault)
        guard let vultToken else { return .zero }
        await BalanceService.shared.updateBalance(for: vultToken)
        
        return vultToken.rawBalance.toBigInt()
    }
    
    func getOrAddVultTokenIfNeeded(to vault: Vault) async -> Coin? {
        var vultToken = getVultToken(for: vault)
        if vultToken == nil {
            await addVultToken(to: vault)
            vultToken = getVultToken(for: vault)
        }
        
        return vultToken
    }
    
    func getVultToken(for vault: Vault) -> Coin? {
        vault.coins.first(where: { $0.chain == .ethereum && $0.ticker == vultTicker })
    }
    
    func addVultToken(to vault: Vault) async {
        let vultTokenMeta = TokensStore.TokenSelectionAssets.first(where: { $0.chain == .ethereum && $0.ticker == vultTicker })
        guard let vultTokenMeta else { return }
        try? await CoinService.addToChain(assets: [vultTokenMeta], to: vault)
    }
    
    func addEthChainIfNeeded(for vault: Vault) async {
        guard !vault.coins.contains(where: { $0.chain == .ethereum && $0.isNativeToken }) else {
            return
        }
        
        let ethNativeToken = TokensStore.TokenSelectionAssets.first(where: { $0.chain == .ethereum && $0.isNativeToken })
        guard let ethNativeToken else { return }
        try? await CoinService.addToChain(assets: [ethNativeToken], to: vault)
    }
}
