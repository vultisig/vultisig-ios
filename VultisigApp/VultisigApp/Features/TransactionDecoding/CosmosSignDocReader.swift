//
//  CosmosSignDocReader.swift
//  VultisigApp
//
//  Reads operation, amount, and counterparty from the protobuf body a co-signer
//  receives. Malformed, mixed, partial, or oversized bodies are refused as a
//  whole; all peer-supplied lengths and varints are bounded.
//

import BigInt
import Foundation

enum CosmosSignDocReader {

    /// What a SignDoc body turned out to be.
    struct Reading: Hashable {
        let operation: DecodedOperation
        let amount: DecodedAmount
        let counterparty: DecodedCounterparty?
    }

    // MARK: - Refusal limits

    /// Real staking bodies are well below this limit.
    private static let maximumBodyBytes = 64 * 1024

    /// Messages in one body. A batched rewards claim sends one per validator.
    private static let maximumMessages = 64

    /// Bounds unknown-field scans.
    private static let maximumFields = 512

    // MARK: - Reading

    /// Reads one complete SignDoc body.
    static func read(bodyBytes base64: String) -> Reading? {
        guard base64.utf8.count <= maximumBodyBytes * 2,
              let body = Data(base64Encoded: base64),
              !body.isEmpty,
              body.count <= maximumBodyBytes
        else { return nil }

        guard let messages = messageBodies(in: body), !messages.isEmpty else { return nil }

        // Every message must decode and agree on one operation.
        var readings: [Reading] = []
        for message in messages {
            guard let reading = read(message) else { return nil }
            readings.append(reading)
        }

        guard let first = readings.first,
              readings.allSatisfy({ $0.operation == first.operation })
        else { return nil }

        // Homogeneous batches have one verb but no single amount or counterparty.
        guard readings.count == 1 else {
            return Reading(operation: first.operation, amount: .unstated, counterparty: nil)
        }
        return first
    }

    /// Reads every `Any` in `TxBody.messages`; partial results are refused.
    private static func messageBodies(in body: Data) -> [(url: String, value: Data)]? {
        var reader = ByteReader(body)
        var messages: [(url: String, value: Data)] = []
        var fields = 0

        while !reader.isAtEnd {
            fields += 1
            guard fields <= maximumFields else { return nil }
            guard let (field, wire) = reader.readTag() else { return nil }

            if field == 1, wire == .lengthDelimited {
                guard messages.count < maximumMessages else { return nil }
                guard let any = reader.readLengthDelimited(),
                      let message = anyContents(any) else { return nil }
                messages.append(message)
            } else {
                guard reader.skip(wire) else { return nil }
            }
        }

        return messages
    }

    /// Reads to the end and preserves protobuf's last-one-wins semantics.
    private static func anyContents(_ any: Data) -> (url: String, value: Data)? {
        var reader = ByteReader(any)
        var url: String?
        var value: Data?
        var fields = 0

        while !reader.isAtEnd {
            fields += 1
            guard fields <= maximumFields else { return nil }
            guard let (field, wire) = reader.readTag() else { return nil }

            switch (field, wire) {
            case (1, .lengthDelimited):
                guard let raw = reader.readLengthDelimited(),
                      let text = String(data: raw, encoding: .utf8) else { return nil }
                url = text
            case (2, .lengthDelimited):
                guard let raw = reader.readLengthDelimited() else { return nil }
                value = raw
            default:
                guard reader.skip(wire) else { return nil }
            }
        }

        // Missing value is legal protobuf and decodes as an empty message.
        guard let url else { return nil }
        return (url, value ?? Data())
    }

    // MARK: - The messages this can corroborate

    /// Names only message types whose values are decoded here.
    private static func read(_ message: (url: String, value: Data)) -> Reading? {
        switch message.url {
        case "/cosmos.staking.v1beta1.MsgDelegate":
            // delegator 1, validator 2, amount 3 (Coin)
            return staking(message.value, operation: .delegate, validatorField: 2, amountField: 3)

        case "/cosmos.staking.v1beta1.MsgUndelegate":
            return staking(message.value, operation: .undelegate, validatorField: 2, amountField: 3)

        case "/cosmos.staking.v1beta1.MsgBeginRedelegate":
            // Destination validator is the relevant counterparty.
            return staking(message.value, operation: .redelegate, validatorField: 3, amountField: 4)

        case "/cosmos.distribution.v1beta1.MsgWithdrawDelegatorReward":
            // Reward withdrawal carries no Coin.
            return staking(message.value, operation: .claimRewards, validatorField: 2, amountField: nil)

        case "/cosmos.bank.v1beta1.MsgSend":
            // from 1, to 2, amount 3 (repeated Coin)
            return staking(message.value, operation: .transfer, validatorField: 2, amountField: 3)

        default:
            return nil
        }
    }

    /// Pulls an address and an optional `Coin` out of a message body.
    private static func staking(
        _ body: Data,
        operation: DecodedOperation,
        validatorField: UInt64,
        amountField: UInt64?
    ) -> Reading? {
        var reader = ByteReader(body)
        var address: String?
        var coins: [(denom: String, amount: BigInt)] = []
        var fields = 0

        while !reader.isAtEnd {
            fields += 1
            guard fields <= maximumFields else { return nil }
            guard let (field, wire) = reader.readTag() else { return nil }

            if field == validatorField, wire == .lengthDelimited {
                guard let raw = reader.readLengthDelimited(),
                      let text = String(data: raw, encoding: .utf8) else { return nil }
                address = text
            } else if let amountField, field == amountField, wire == .lengthDelimited {
                guard let raw = reader.readLengthDelimited(), let parsed = coin(raw) else { return nil }
                coins.append(parsed)
            } else {
                guard reader.skip(wire) else { return nil }
            }
        }

        // Multi-denom sends have no single amount; an absent address proves nothing.
        guard let address, !address.isEmpty else { return nil }

        let amount: DecodedAmount = coins.count == 1
            ? .units(coins[0].amount, of: .denom(coins[0].denom))
            : .unstated
        return Reading(
            operation: operation,
            amount: amount,
            counterparty: operation == .transfer ? .contract(address) : .validator(address)
        )
    }

    /// `cosmos.base.v1beta1.Coin` — denom 1, amount 2, both strings.
    private static func coin(_ body: Data) -> (denom: String, amount: BigInt)? {
        var reader = ByteReader(body)
        var denom: String?
        var amount: BigInt?
        var fields = 0

        while !reader.isAtEnd {
            fields += 1
            guard fields <= maximumFields else { return nil }
            guard let (field, wire) = reader.readTag() else { return nil }

            switch (field, wire) {
            case (1, .lengthDelimited):
                guard let raw = reader.readLengthDelimited(),
                      let text = String(data: raw, encoding: .utf8) else { return nil }
                denom = text
            case (2, .lengthDelimited):
                guard let raw = reader.readLengthDelimited(),
                      let text = String(data: raw, encoding: .utf8),
                      let value = BigInt(text), value >= 0 else { return nil }
                amount = value
            default:
                guard reader.skip(wire) else { return nil }
            }
        }

        guard let denom, !denom.isEmpty, let amount else { return nil }
        return (denom, amount)
    }

    // MARK: - Bounds-checked protobuf reader

    /// Handles malformed peer input and non-zero-index `Data` slices without traps.
    private struct ByteReader {
        private let bytes: Data
        private var index: Data.Index

        init(_ bytes: Data) {
            self.bytes = bytes
            self.index = bytes.startIndex
        }

        var isAtEnd: Bool { index >= bytes.endIndex }

        /// Base-128 varint that refuses UInt64 overflow.
        mutating func readVarint() -> UInt64? {
            var value: UInt64 = 0
            var shift: UInt64 = 0

            while shift < 64 {
                guard index < bytes.endIndex else { return nil }
                let byte = bytes[index]
                index = bytes.index(after: index)

                let payload = UInt64(byte & 0x7F)
                // Only one payload bit fits at shift 63.
                if shift == 63, payload > 1 { return nil }

                value |= payload << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
            }

            return nil
        }

        mutating func readTag() -> (field: UInt64, wire: WireType)? {
            guard let tag = readVarint(), let wire = WireType(rawValue: tag & 0x07) else { return nil }
            return (tag >> 3, wire)
        }

        mutating func readLengthDelimited() -> Data? {
            guard let length = readVarint(), length <= UInt64(Int.max) else { return nil }
            let count = Int(length)
            guard count >= 0, bytes.distance(from: index, to: bytes.endIndex) >= count else { return nil }

            let end = bytes.index(index, offsetBy: count)
            defer { index = end }
            return bytes[index..<end]
        }

        mutating func skip(_ wire: WireType) -> Bool {
            switch wire {
            case .varint: return readVarint() != nil
            case .fixed64: return advance(by: 8)
            case .lengthDelimited: return readLengthDelimited() != nil
            case .fixed32: return advance(by: 4)
            // Deprecated groups are not valid for supported SignDocs.
            case .startGroup, .endGroup: return false
            }
        }

        private mutating func advance(by count: Int) -> Bool {
            guard bytes.distance(from: index, to: bytes.endIndex) >= count else { return false }
            index = bytes.index(index, offsetBy: count)
            return true
        }
    }

    /// Protobuf wire types from the low three tag bits.
    private enum WireType: UInt64 {
        case varint = 0
        case fixed64 = 1
        case lengthDelimited = 2
        case startGroup = 3
        case endGroup = 4
        case fixed32 = 5
    }
}
