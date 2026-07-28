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
		/// Total number of unspent outputs Blockchair holds for this address,
		/// mempool ones included. The `utxo` array is capped by the request's
		/// `limit`, so this is the only way to tell a complete page from a
		/// truncated one — and it is what drives pagination in
		/// `BlockchairService`.
		let unspentOutputCount: Int?

		// Blockchair sends snake_case over the wire and the `JSONDecoder` used
		// by `HTTPClient` applies no key strategy, so every multi-word field
		// needs an explicit mapping.
		enum CodingKeys: String, CodingKey {
			case scriptHex = "script_hex"
			case balance
			case unspentOutputCount = "unspent_output_count"
		}

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
        /// Whether the provider considers this output spendable. Blockchair's
        /// Bitcoin responses omit the field entirely, so it is optional and
        /// **absent means spendable** — matching the SDK's `is_spendable !==
        /// false`. Only an explicit `false` disqualifies an output.
        let isSpendable: Bool?

        // Blockchair returns `transaction_hash` and `block_id` (snake_case) over the
        // wire. The default `JSONDecoder` we use through `HTTPClient` doesn't apply
        // `.convertFromSnakeCase`, so map the fields explicitly here. `index` and
        // `value` are already a single word and need no remap.
        enum CodingKeys: String, CodingKey {
            case blockId = "block_id"
            case transactionHash = "transaction_hash"
            case index
            case value
            case isSpendable = "is_spendable"
        }

        /// `isSpendable` defaults to `nil` because that is the wire shape
        /// Blockchair actually sends for Bitcoin — the field is simply absent.
        init(blockId: Int?, transactionHash: String?, index: Int?, value: Int?, isSpendable: Bool? = nil) {
            self.blockId = blockId
            self.transactionHash = transactionHash
            self.index = index
            self.value = value
            self.isSpendable = isSpendable
        }
    }
}

extension Blockchair.BlockchairUtxo {
    /// Identity of an output on-chain.
    ///
    /// A paginated fetch can see the same output twice when the address's
    /// UTXO set shifts between two page requests (Blockchair returns the list
    /// newest-first, so one new entry slides everything down by one). A
    /// duplicated outpoint in the candidate set would let the planner build a
    /// transaction that spends the same input twice, which the network
    /// rejects — so pages are merged on this key.
    struct OutPoint: Hashable {
        let transactionHash: String
        let index: Int
    }

    /// `nil` when the row is missing the fields needed to identify the output.
    /// Such rows are unusable downstream and are dropped there; they simply
    /// cannot participate in de-duplication.
    var outPoint: OutPoint? {
        guard let transactionHash, !transactionHash.isEmpty, let index else {
            return nil
        }
        return OutPoint(transactionHash: transactionHash, index: index)
    }

    /// Whether this output may be offered to transaction planning. Mirrors the
    /// SDK's `is_spendable !== false && block_id > 0`.
    ///
    /// **Confirmed only.** Blockchair reports mempool outputs with
    /// `block_id == -1` and counts them in the address balance. An unconfirmed
    /// output can still be replaced or evicted, and the response carries no
    /// ancestry, so there is no way to tell our own change from an inbound
    /// zero-conf payment that a sender can still double-spend. Spending either
    /// produces a child transaction that dies with its parent — and the MPC
    /// pairing window leaves minutes for that to happen between selection and
    /// broadcast. A missing `block_id` is treated the same way: an output whose
    /// depth we could not establish is not spent.
    ///
    /// **Not explicitly unspendable.** `is_spendable` is absent from
    /// Blockchair's Bitcoin responses, so absent means spendable and only an
    /// explicit `false` disqualifies an output.
    var isSpendableCandidate: Bool {
        guard isSpendable != false else { return false }
        guard let blockId, blockId > 0 else { return false }
        return true
    }
}
