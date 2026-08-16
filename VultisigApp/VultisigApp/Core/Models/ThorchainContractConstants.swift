//
//  ThorchainContractConstants.swift
//  VultisigApp
//
//  Created by Vultisig on 2025/01/07.
//
//  Addresses of the Rujira/THORChain wasm contracts the app builds messages
//  against. Kept in one place because each is a chain constant rather than a
//  property of the form that spends it, and several are shared by a stake and
//  its matching unstake builder.
//

import Foundation

enum RUJIStakingConstants {
    static let contract = "thor13g83nn5ef4qzqeafp0508dnvkvm0zqr3sj7eefcn5umu65gqluusrml5cr"
}

enum TCYAutoCompoundConstants {
    static let contract = "thor1z7ejlk5wk2pxh9nfwjzkkdnrq4p2f5rjcpudltv0gh282dwfz6nq9g2cr0"
}

/// Rujira `rujira-staking` "liquid bond" contract for Bonded RUNE (bRUNE).
/// Stake bonds `x/brune` (`{"liquid":{"bond":{}}}`) and mints the
/// auto-compounding receipt `x/staking-x/brune` (ybRUNE); unstake unbonds it
/// (`{"liquid":{"unbond":{}}}`). NAV is the contract's `{"status":{}}`
/// `liquid_bond_size / liquid_bond_shares` ratio.
enum BRUNEStakingConstants {
    static let contract = "thor179fex2rxd45caedmz4hxsnu42sw20lu0djyh4yukyh965sq8muuqptru2g"
}
