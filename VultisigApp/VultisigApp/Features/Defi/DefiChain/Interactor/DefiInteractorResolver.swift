//
//  DefiInteractorResolver.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/11/2025.
//

enum DefiInteractorResolver {
    static func stakeInteractor(for chain: Chain) -> StakeInteractor? {
        switch chain {
        case .thorChain:
            return THORChainStakeInteractor()
        case .mayaChain:
            return MayaChainStakeInteractor()
        default:
            return nil  // Chain doesn't support DeFi Stake Tab
        }
    }
<<<<<<< HEAD
    
    static func bondInteractor(for chain: Chain) -> BondInteractor? {
=======

    static func bondInteractor(for chain: Chain) -> BondInteractor {
>>>>>>> 186671542ac1b63de085bacb2f784ce5c89644a3
        switch chain {
        case .thorChain:
            return THORChainBondInteractor()
        case .mayaChain:
            return MayaChainBondInteractor()
        default:
            return nil  // Chain doesn't support DeFi Bond Tab
        }
    }
<<<<<<< HEAD
    
    static func lpsInteractor(for chain: Chain) -> LPsInteractor? {
=======

    static func lpsInteractor(for chain: Chain) -> LPsInteractor {
>>>>>>> 186671542ac1b63de085bacb2f784ce5c89644a3
        switch chain {
        case .thorChain:
            return THORChainLPsInteractor()
        case .mayaChain:
            return MayaChainLPsInteractor()
        default:
            return nil  // Chain doesn't support DeFi LPs Tab
        }
    }
}
