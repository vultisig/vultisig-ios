//
//  CosmosSerializedParser.swift
//  VultisigApp
//
//  Parser for Cosmos serialized transaction data
//  Handles both protobuf (tx_bytes) and Amino JSON (tx) formats
//

import Foundation

enum CosmosSerializedParser {

    struct ParsedResult {
        let txBytes: String
    }

    enum ParseError: Error, LocalizedError {
        case missingSerialized
        case emptySerialized
        case missingTxBytes
        case missingSignatures
        case invalidFormat(String)
        case encodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingSerialized:
                return "Serialized Cosmos transaction data is missing"
            case .emptySerialized:
                return "Serialized Cosmos transaction data is empty"
            case .missingTxBytes:
                return "tx_bytes field is missing or empty in serialized data"
            case .missingSignatures:
                return "Amino JSON transaction missing signatures"
            case .invalidFormat(let details):
                return "Invalid serialized format: \(details)"
            case .encodingFailed(let details):
                return "Failed to encode Amino JSON transaction: \(details)"
            }
        }
    }

    /// Parses serialized Cosmos transaction data and extracts tx_bytes
    /// Handles both protobuf format (with tx_bytes) and Amino JSON format (with tx)
    static func parse(_ serialized: String?) throws -> ParsedResult {
        guard let serialized = serialized, !serialized.isEmpty else {
            throw ParseError.emptySerialized
        }

        let trimmed = serialized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ParseError.emptySerialized
        }

        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalidFormat("expected valid JSON")
        }

        // Try protobuf format first (has tx_bytes directly)
        if let txBytes = json["tx_bytes"] as? String, !txBytes.isEmpty {
            return ParsedResult(txBytes: txBytes)
        }

        // Try Amino JSON format (has tx field with StdTx)
        if let tx = json["tx"] {
            return try parseAminoFormat(tx: tx)
        }

        throw ParseError.invalidFormat("JSON does not contain tx_bytes (protobuf) or tx (Amino JSON) field")
    }

    /// Parses Amino JSON format - encodes the tx object as JSON string, then base64
    private static func parseAminoFormat(tx: Any) throws -> ParsedResult {
        guard let txDict = tx as? [String: Any] else {
            throw ParseError.invalidFormat("tx field is not a valid object")
        }

        // Verify signatures exist
        if let signatures = txDict["signatures"] as? [Any], signatures.isEmpty {
            throw ParseError.missingSignatures
        } else if txDict["signatures"] == nil {
            throw ParseError.missingSignatures
        }

        // Encode the tx object as JSON string
        guard let txData = try? JSONSerialization.data(withJSONObject: txDict, options: [.sortedKeys]),
              let txJsonString = String(data: txData, encoding: .utf8) else {
            throw ParseError.encodingFailed("Failed to serialize tx to JSON")
        }

        // Convert to base64
        guard let txBytes = txJsonString.data(using: .utf8)?.base64EncodedString() else {
            throw ParseError.encodingFailed("Failed to encode JSON to base64")
        }

        return ParsedResult(txBytes: txBytes)
    }

    /// Computes the transaction hash from serialized data
    /// Returns uppercase hex string (no 0x prefix)
    static func getTransactionHash(from serialized: String?) -> String {
        guard let result = try? parse(serialized),
              let txData = Data(base64Encoded: result.txBytes) else {
            return ""
        }
        return txData.sha256().toHexString().uppercased()
    }
}
