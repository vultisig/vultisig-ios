//
//  SolanaTokenMetadata.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 09/07/24.
//

import Foundation

public struct SolanaFmTokenInfo: Codable {
    struct TokenList: Codable {
        let name: String?
        let symbol: String?
        let image: String?
        let extensions: Extensions?
        let chainId: Int?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try? container.decode(String.self, forKey: .name)
            symbol = try? container.decode(String.self, forKey: .symbol)
            image = try? container.decode(String.self, forKey: .image)
            extensions = try? container.decode(Extensions.self, forKey: .extensions)
            chainId = try? container.decode(Int.self, forKey: .chainId)
        }
    }

    struct Extensions: Codable {
        let coingeckoId: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            coingeckoId = try? container.decode(String.self, forKey: .coingeckoId)
        }
    }

    struct TokenMetadata: Codable {
        struct OnChainInfo: Codable {
            let name: String?
            let symbol: String?

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try? container.decode(String.self, forKey: .name)
                symbol = try? container.decode(String.self, forKey: .symbol)
            }
        }

        let onChainInfo: OnChainInfo?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            onChainInfo = try? container.decode(OnChainInfo.self, forKey: .onChainInfo)
        }
    }

    let mint: String?
    let decimals: Int?
    let tokenList: TokenList?
    let tokenMetadata: TokenMetadata?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mint = try? container.decode(String.self, forKey: .mint)
        decimals = try? container.decode(Int.self, forKey: .decimals)
        tokenList = try? container.decode(TokenList.self, forKey: .tokenList)
        tokenMetadata = try? container.decode(TokenMetadata.self, forKey: .tokenMetadata)
    }
}
