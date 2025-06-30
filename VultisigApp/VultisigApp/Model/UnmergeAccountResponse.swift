//
//  UnmergeAccountResponse.swift
//  VultisigApp
//
//  Created on 2025/01/03.
//

struct UnmergeAccountResponse: Decodable {
    let data: ResponseData

    struct ResponseData: Decodable {
        let node: Node?
        
        struct Node: Decodable {
            let merge: AccountMerge?
            
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
                            
                            struct Metadata: Decodable {
                                let symbol: String
                            }
                        }
                    }
                }
            }
        }
    }
} 