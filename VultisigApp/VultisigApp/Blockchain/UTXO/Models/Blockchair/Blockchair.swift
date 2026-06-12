//
//  Blockchair.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/03/2024.
//

import Foundation
import WalletCore

struct BlockchairResponse: Codable {
	let data: [String: Blockchair]
	/// Request-level metadata. `context.state` is the height of the latest
	/// block Blockchair has indexed — i.e. the current chain tip — which the
	/// QBTC claim flow uses to compute per-UTXO confirmations. Optional so
	/// older/partial payloads (and existing decode tests) keep decoding.
	let context: Context?

	struct Context: Codable {
		/// Latest indexed block height (chain tip).
		let state: Int?
	}
}

struct Blockchair: Codable {
	let address: BlockchairAddress?
	let utxo: [BlockchairUtxo]?

    struct BlockchairAddress: Codable {
		let scriptHex: String?
		let balance: Int?

		var balanceInBTC: String {
			formatAsBitcoin(balance ?? 0)
		}
		// Helper function to format an amount in satoshis as Bitcoin
        func formatAsBitcoin(_ satoshis: Int) -> String {
			let btcValue = Decimal(satoshis) / 100_000_000.0 // Convert satoshis to BTC
            return btcValue.formatToDecimal(digits: 8)
		}
	}

    struct BlockchairUtxo: Codable {
        let blockId: Int?
        let transactionHash: String?
        let index: Int?
        let value: Int?

        // Blockchair returns `transaction_hash` and `block_id` (snake_case) over the
        // wire. The default `JSONDecoder` we use through `HTTPClient` doesn't apply
        // `.convertFromSnakeCase`, so map the fields explicitly here. `index` and
        // `value` are already a single word and need no remap.
        enum CodingKeys: String, CodingKey {
            case blockId = "block_id"
            case transactionHash = "transaction_hash"
            case index
            case value
        }
    }
}
