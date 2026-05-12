//
//  AccountRootData.swift
//  VultisigApp
//
//  Created on 2025/01/03.
//

import Foundation

struct AccountRootData: Decodable {
    let data: ResponseData

    struct ResponseData: Decodable {
        let node: AccountNode?

        struct AccountNode: Decodable {
            let merge: AccountMerge?
            let stakingV2: [StakingV2]?

            struct AccountMerge: Decodable {
                let accounts: [MergeAccount]

                struct MergeAccount: Decodable {
                    let pool: Pool
                    let size: Size
                    let shares: String

                    struct Size: Decodable {
                        let amount: String
                    }

                    struct Pool: Decodable {
                        let mergeAsset: MergeAsset

                        struct MergeAsset: Decodable {
                            let metadata: Metadata
                        }
                    }
                }
            }

            struct StakingV2: Decodable {
                let account: String
                let bonded: Bonded
                let pendingRevenue: PendingRevenue?
                let pool: Pool?
            }

            struct Pool: Decodable {
                let summary: Summary?
            }

            struct Summary: Decodable {
                let apr: APR?
            }

            struct APR: Decodable {
                /// Bigint scalar from the Rujira GraphQL schema. Decimal values (rates, prices) are
                /// scaled to 12 decimal places — divide by 10^12 to get the fractional rate (e.g.
                /// `11623890337` → `0.011624` → `1.16%`).
                let value: String
                /// `AVAILABLE` | `NOT_APPLICABLE` | `SOON`. Treat anything but `AVAILABLE` as no APR.
                let status: String?

                /// Fractional rate (e.g. `0.0116` for 1.16% APR), or `nil` when the pool isn't
                /// `AVAILABLE` or the value can't be parsed.
                var fractionalRate: Double? {
                    if let status, status != "AVAILABLE" { return nil }
                    guard let raw = Decimal(string: value) else { return nil }
                    let scaled = raw / pow(10, 12)
                    return NSDecimalNumber(decimal: scaled).doubleValue
                }
            }

            struct Bonded: Decodable {
                let amount: String
                let asset: Asset
            }

            struct PendingRevenue: Decodable {
                let amount: String
                let asset: Asset
            }

            struct Asset: Decodable {
                let metadata: Metadata?
            }

            struct Metadata: Decodable {
                let symbol: String
            }
        }
    }
}
