//
//  AccountRootData.swift
//  VultisigApp
//
//  Created on 2025/01/03.
//

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
                let value: String
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
