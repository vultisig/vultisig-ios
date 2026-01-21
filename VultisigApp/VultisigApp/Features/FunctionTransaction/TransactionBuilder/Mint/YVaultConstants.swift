//
//  YVaultConstants.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 18/11/2025.
//

import Foundation

enum YVaultConstants {
    private static let yRuneContract = "thor1mlphkryw5g54yfkrp6xpqzlpv4f8wh6hyw27yyg4z2els8a9gxpqhfhekt"
    private static let yTcyContract = "thor1h0hr0rm3dawkedh44hlrmgvya6plsryehcr46yda2vj0wfwgq5xqrs86px"

    // Affiliate contract configuration for 10 basis points (0.1%) fees
    static let affiliateContractAddress = "thor1v3f7h384r8hw6r3dtcgfq6d5fq842u6cjzeuu8nr0cp93j7zfxyquyrfl8"
    static let affiliateAddress = "thor1svfwxevnxtm4ltnw92hrqpqk4vzuzw9a4jzy04" // Your affiliate address
    static let affiliateFeeBasisPoints = 10 // 10 basis points = 0.1%

    static let contracts: [String: String] = [
        "rune": yRuneContract,
        "tcy": yTcyContract,
        "yrune": yRuneContract,
        "ytcy": yTcyContract
    ]

    static let receiptDenominations: [String: String] = [
        "rune": "x/nami-index-nav-\(yRuneContract)-rcpt",
        "tcy": "x/nami-index-nav-\(yTcyContract)-rcpt",
        "yrune": "x/nami-index-nav-\(yRuneContract)-rcpt",
        "ytcy": "x/nami-index-nav-\(yTcyContract)-rcpt"
    ]
}
