//
//  ThorchainMergeTokens.swift
//  VultisigApp
//
//  Created by Vultisig on 2025/01/07.
//

import Foundation

/// Information about a token that can be merged/unmerged
struct TokenMergeInfo: Codable {
    let denom: String
    let wasmContractAddress: String
}

/// Common configuration for THORChain merge tokens
enum ThorchainMergeTokens {
    /// List of tokens that support merge/unmerge functionality
    static let tokensToMerge: [TokenMergeInfo] = [
        TokenMergeInfo(denom: "thor.kuji", wasmContractAddress: "thor14hj2tavq8fpesdwxxcu44rty3hh90vhujrvcmstl4zr3txmfvw9s3p2nzy"),
        TokenMergeInfo(denom: "thor.rkuji", wasmContractAddress: "thor1yyca08xqdgvjz0psg56z67ejh9xms6l436u8y58m82npdqqhmmtqrsjrgh"),
        TokenMergeInfo(denom: "thor.fuzn", wasmContractAddress: "thor1suhgf5svhu4usrurvxzlgn54ksxmn8gljarjtxqnapv8kjnp4nrsw5xx2d"),
        TokenMergeInfo(denom: "thor.nstk", wasmContractAddress: "thor1cnuw3f076wgdyahssdkd0g3nr96ckq8cwa2mh029fn5mgf2fmcmsmam5ck"),
        TokenMergeInfo(denom: "thor.wink", wasmContractAddress: "thor1yw4xvtc43me9scqfr2jr2gzvcxd3a9y4eq7gaukreugw2yd2f8tsz3392y"),
        TokenMergeInfo(denom: "thor.lvn", wasmContractAddress: "thor1ltd0maxmte3xf4zshta9j5djrq9cl692ctsp9u5q0p9wss0f5lms7us4yf")
    ]
}

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
