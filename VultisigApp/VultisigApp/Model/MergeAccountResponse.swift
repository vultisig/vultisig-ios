//
//  Untitled.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 21/05/25.
//

struct MergeAccountResponse: Decodable {
    let data: ResponseData

    struct ResponseData: Decodable {
        let node: Node?

        struct Node: Decodable {
            let merge: AccountMerge?

            struct AccountMerge: Decodable {
                let accounts: [MergeAccount]?

                struct MergeAccount: Decodable {
                    let pool: Pool
                    let size: Size
                    let shares: String

                    struct Pool: Decodable {
                        let mergeAsset: MergeAsset

                        struct MergeAsset: Decodable {
                            let metadata: Metadata

                            struct Metadata: Decodable {
                                let symbol: String
                            }
                        }
                    }

                    struct Size: Decodable {
                        let amount: String
                    }
                }
            }
        }
    }
}
