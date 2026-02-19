//
//  CustomMessageDecoder.swift
//  VultisigApp
//

import Foundation

struct CustomMessageDecoder {

    /// Decodes the display message for a CustomMessagePayload.
    /// Handles method/chain-specific formats (TRON TIP-191, personal_sign hex, etc.)
    /// and falls back to generic contract-call decoding for unknown formats.
    static func decode(_ payload: CustomMessagePayload) async -> String? {
        switch payload.method {
        case "sign_message" where payload.chain.lowercased() == "tron":
            return decodeTronSignMessage(payload.message)

        case "personal_sign":
            return decodePersonalSign(payload.message)

        case "eth_signTypedData_v4":
            return decodeTypedData(payload.message)

        default:
            return await payload.message.decodedExtensionMemoAsync()
        }
    }

    // MARK: - Private

    /// TRON: hex -> UTF-8 -> strip "\x19TRON Signed Message:\n{length}" prefix
    private static func decodeTronSignMessage(_ message: String) -> String? {
        guard message.hasPrefix("0x") else { return nil }
        let hex = String(message.dropFirst(2))
        guard let data = Data(hexString: hex),
              let decoded = String(data: data, encoding: .utf8) else { return nil }

        let prefix = "\u{19}TRON Signed Message:\n"
        guard decoded.hasPrefix(prefix) else { return decoded }

        let afterPrefix = String(decoded.dropFirst(prefix.count))
        let lengthString = String(afterPrefix.prefix(while: { $0.isNumber }))
        guard let length = Int(lengthString) else { return decoded }
        let afterLength = Data(afterPrefix.dropFirst(lengthString.count).utf8)
        guard afterLength.count >= length,
              let messageBody = String(data: afterLength.prefix(length), encoding: .utf8) else {
            return decoded
        }
        return messageBody
    }

    /// personal_sign: hex -> UTF-8
    private static func decodePersonalSign(_ message: String) -> String? {
        guard message.hasPrefix("0x") else { return nil }
        let hex = String(message.dropFirst(2))
        guard let data = Data(hexString: hex),
              let decoded = String(data: data, encoding: .utf8) else { return nil }
        return decoded
    }

    /// eth_signTypedData_v4: pretty-print JSON
    private static func decodeTypedData(_ message: String) -> String? {
        guard let jsonData = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData),
              let prettyData = try? JSONSerialization.data(
                withJSONObject: json,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return prettyString
    }
}
