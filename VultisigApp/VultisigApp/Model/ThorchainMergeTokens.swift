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