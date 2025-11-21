//
//  DefiInteractorResolver.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/11/2025.
//

enum DefiInteractorResolver {
    static func stakeInteractor(for chain: Chain) -> StakeInteractor {
        switch chain {
        case .thorChain:
            return THORChainStakeInteractor()
        default:
            fatalError("Chain \(chain.name) doesn't support DeFi Stake Tab")
        }
    }
    
    static func bondInteractor(for chain: Chain) -> BondInteractor {
        switch chain {
        case .thorChain:
            return THORChainBondInteractor()
        default:
            fatalError("Chain \(chain.name) doesn't support DeFi Bond Tab")
        }
    }
    
    static func lpsInteractor(for chain: Chain) -> LPsInteractor {
        switch chain {
        case .thorChain:
            return THORChainLPsInteractor()
        default:
            fatalError("Chain \(chain.name) doesn't support DeFi LPs Tab")
        }
    }
}
