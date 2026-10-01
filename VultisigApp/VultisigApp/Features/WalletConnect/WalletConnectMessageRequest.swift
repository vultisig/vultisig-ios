//
//  WalletConnectMessageRequest.swift
//  VultisigApp
//

import Foundation

enum WalletConnectRequestID: Equatable, Hashable, ExpressibleByStringLiteral {
    case string(String)
    case integer(Int64)

    init(stringLiteral value: String) {
        self = .string(value)
    }

    var stringValue: String {
        switch self {
        case .string(let value): return value
        case .integer(let value): return value.description
        }
    }
}

struct WalletConnectIncomingRequest: Equatable {
    let topic: String
    let requestId: WalletConnectRequestID
    let method: String
    let chainId: String?
    let paramsJSON: String
    let dappName: String
    let dappURL: String
    let dappIcon: String?
    let verifyContext: WalletConnectVerifyContext?
}

struct WalletConnectAuthenticationRequest: Equatable {
    let requestId: WalletConnectRequestID
}

struct WalletConnectMessageRequest: Identifiable, Equatable {
    var id: String { requestId.stringValue }

    let topic: String
    let requestId: WalletConnectRequestID
    let method: String
    let chain: Chain
    let message: String
    let displayMessage: String
    let address: String
    let vaultPubKeyECDSA: String
    let vaultLocalPartyID: String
    let dappMetadata: DAppMetadata
    let verifyContext: WalletConnectVerifyContext?

    var customMessagePayload: CustomMessagePayload {
        CustomMessagePayload(
            method: method,
            message: message,
            vaultPublicKeyECDSA: vaultPubKeyECDSA,
            vaultLocalPartyID: vaultLocalPartyID,
            chain: chain.name,
            decodedMessage: displayMessage,
            dappMetadata: dappMetadata.isEmpty ? nil : dappMetadata
        )
    }
}

enum WalletConnectMessageRequestError: LocalizedError, Equatable {
    case unsupportedMethod(String)
    case invalidParams(String)
    case missingChainId
    case unsupportedChain(String)
    case missingBoundVault(String)
    case missingBoundAccount(String)
    case invalidSignature(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedMethod(let method):
            return String(format: "walletConnectMessageErrorUnsupportedMethod".localized, method)
        case .invalidParams(let reason):
            return String(format: "walletConnectMessageErrorInvalidParams".localized, reason)
        case .missingChainId:
            return "walletConnectMessageErrorMissingChainId".localized
        case .unsupportedChain(let chainId):
            return String(format: "walletConnectMessageErrorUnsupportedChain".localized, chainId)
        case .missingBoundVault:
            return "walletConnectMessageErrorMissingBoundVault".localized
        case .missingBoundAccount:
            return "walletConnectMessageErrorMissingBoundAccount".localized
        case .invalidSignature(let reason):
            return String(format: "walletConnectMessageErrorInvalidSignature".localized, reason)
        }
    }
}

struct WalletConnectMessageRequestParser {
    func parse(_ request: WalletConnectIncomingRequest) throws -> WalletConnectParsedMessageRequest {
        switch request.method {
        case "personal_sign":
            return try parsePersonalSign(request)
        case "eth_signTypedData_v4":
            return try parseTypedDataV4(request)
        default:
            throw WalletConnectMessageRequestError.unsupportedMethod(request.method)
        }
    }

    private func parsePersonalSign(_ request: WalletConnectIncomingRequest) throws -> WalletConnectParsedMessageRequest {
        let values = try parseArray(request.paramsJSON)
        guard values.count >= 2 else {
            throw WalletConnectMessageRequestError.invalidParams("personal_sign requires message and address")
        }
        let first = try stringValue(values[0], label: "first personal_sign parameter")
        let second = try stringValue(values[1], label: "second personal_sign parameter")
        let message: String
        let address: String
        if first.isEVMAddressLike, !second.isEVMAddressLike {
            address = first
            message = second
        } else if second.isEVMAddressLike {
            message = first
            address = second
        } else {
            throw WalletConnectMessageRequestError.invalidParams("personal_sign requires an EVM address")
        }
        return WalletConnectParsedMessageRequest(
            method: request.method,
            caip2ChainId: request.chainId,
            address: address,
            message: message,
            displayMessage: WalletConnectMessageRequestParser.displayPersonalMessage(message)
        )
    }

    private func parseTypedDataV4(_ request: WalletConnectIncomingRequest) throws -> WalletConnectParsedMessageRequest {
        let values = try parseArray(request.paramsJSON)
        guard values.count >= 2 else {
            throw WalletConnectMessageRequestError.invalidParams("eth_signTypedData_v4 requires address and typed data")
        }
        let address = try stringValue(values[0], label: "typed-data address")
        guard address.isEVMAddressLike else {
            throw WalletConnectMessageRequestError.invalidParams("eth_signTypedData_v4 first parameter must be an EVM address")
        }
        let typedData = try rawJSONString(for: values[1], source: request.paramsJSON)
        return WalletConnectParsedMessageRequest(
            method: request.method,
            caip2ChainId: request.chainId,
            address: address,
            message: typedData,
            displayMessage: WalletConnectMessageRequestParser.displayTypedData(typedData)
        )
    }

    private func parseArray(_ json: String) throws -> [Any] {
        guard let data = json.data(using: .utf8) else {
            throw WalletConnectMessageRequestError.invalidParams("params are not UTF-8")
        }
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let array = object as? [Any] else {
            throw WalletConnectMessageRequestError.invalidParams("params must be a JSON array")
        }
        return array
    }

    private func stringValue(_ value: Any, label: String) throws -> String {
        guard let string = value as? String, !string.isEmpty else {
            throw WalletConnectMessageRequestError.invalidParams("\(label) must be a non-empty string")
        }
        return string
    }

    private func rawJSONString(for value: Any, source: String) throws -> String {
        if let string = value as? String {
            return string
        }
        if let preserved = preserveSecondParamJSON(from: source) {
            return preserved
        }
        guard JSONSerialization.isValidJSONObject(value) else {
            throw WalletConnectMessageRequestError.invalidParams("typed data must be a JSON object or string")
        }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    private func preserveSecondParamJSON(from source: String) -> String? {
        guard let comma = findTopLevelComma(in: source) else { return nil }
        var tail = source[source.index(after: comma)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard tail.last == "]" else { return nil }
        tail.removeLast()
        return tail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func findTopLevelComma(in source: String) -> String.Index? {
        var inString = false
        var isEscaped = false
        var depth = 0
        for index in source.indices {
            let char = source[index]
            if isEscaped {
                isEscaped = false
                continue
            }
            if inString {
                if char == "\\" { isEscaped = true }
                if char == "\"" { inString = false }
                continue
            }
            switch char {
            case "\"": inString = true
            case "[", "{": depth += 1
            case "]", "}": depth -= 1
            case "," where depth == 1: return index
            default: break
            }
        }
        return nil
    }

    static func displayPersonalMessage(_ message: String) -> String {
        guard message.hasPrefix("0x"), let data = Data(hexString: message), !data.isEmpty,
              let decoded = String(data: data, encoding: .utf8), !decoded.isEmpty else {
            return message
        }
        return decoded
    }

    static func displayTypedData(_ message: String) -> String {
        guard let data = message.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return message
        }
        return String(bytes: pretty, encoding: .utf8) ?? message
    }
}

struct WalletConnectParsedMessageRequest: Equatable {
    let method: String
    let caip2ChainId: String?
    let address: String
    let message: String
    let displayMessage: String
}

struct WalletConnectEVMChainResolver {
    func resolve(_ caip2ChainId: String?) throws -> Chain {
        guard let caip2ChainId, !caip2ChainId.isEmpty else {
            throw WalletConnectMessageRequestError.missingChainId
        }
        let parts = caip2ChainId.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == WalletConnectEVMNamespaceAdapter.namespace,
              let chainId = Int(parts[1]) else {
            throw WalletConnectMessageRequestError.unsupportedChain(caip2ChainId)
        }
        guard let chain = Chain.allCases.first(where: { $0.chainType == .EVM && $0.chainID == chainId && $0.isSupported }) else {
            throw WalletConnectMessageRequestError.unsupportedChain(caip2ChainId)
        }
        return chain
    }
}

struct WalletConnectMessageRequestBuilder {
    private let parser = WalletConnectMessageRequestParser()
    private let chainResolver = WalletConnectEVMChainResolver()

    func build(
        incoming request: WalletConnectIncomingRequest,
        binding: WalletConnectSessionBinding?,
        vaults: [Vault]
    ) throws -> WalletConnectMessageRequest {
        let parsed = try parser.parse(request)
        let chain = try chainResolver.resolve(parsed.caip2ChainId)
        guard let binding else {
            throw WalletConnectMessageRequestError.missingBoundVault(request.topic)
        }
        guard let vault = vaults.first(where: { $0.pubKeyECDSA == binding.vaultPubKeyECDSA }) else {
            throw WalletConnectMessageRequestError.missingBoundVault(request.topic)
        }
        guard vault.walletConnectEVMAccounts.contains(where: {
            $0.chainReference == parsed.caip2ChainId && $0.address.caseInsensitiveCompare(parsed.address) == .orderedSame
        }) else {
            throw WalletConnectMessageRequestError.missingBoundAccount(parsed.address)
        }
        return WalletConnectMessageRequest(
            topic: request.topic,
            requestId: request.requestId,
            method: parsed.method,
            chain: chain,
            message: parsed.message,
            displayMessage: parsed.displayMessage,
            address: parsed.address,
            vaultPubKeyECDSA: vault.pubKeyECDSA,
            vaultLocalPartyID: vault.localPartyID,
            dappMetadata: DAppMetadata(
                name: request.dappName,
                url: request.dappURL,
                iconURL: request.dappIcon ?? ""
            ),
            verifyContext: request.verifyContext
        )
    }
}

struct WalletConnectEVMSignatureFormatter {
    func normalizedSignature(_ signatureHex: String) throws -> String {
        let raw = signatureHex.stripHexPrefix()
        guard raw.count == 130, raw.allSatisfy(\.isHexDigit) else {
            throw WalletConnectMessageRequestError.invalidSignature("expected 65-byte ECDSA signature")
        }
        let recoveryStart = raw.index(raw.endIndex, offsetBy: -2)
        let body = String(raw[..<recoveryStart])
        var recovery = String(raw[recoveryStart...]).lowercased()
        if recovery == "00" { recovery = "1b" }
        if recovery == "01" { recovery = "1c" }
        guard recovery == "1b" || recovery == "1c" else {
            throw WalletConnectMessageRequestError.invalidSignature("invalid EVM recovery id")
        }
        return "0x\(body)\(recovery)".lowercased()
    }
}

struct WalletConnectVerifyContext: Equatable {
    enum Validation: String, Equatable {
        case unknown
        case valid
        case invalid
        case scam
    }

    let origin: String
    let validation: Validation

    var titleLocalizationKey: String {
        switch validation {
        case .valid: return "walletConnectVerifyValidTitle"
        case .unknown: return "walletConnectVerifyUnknownTitle"
        case .invalid: return "walletConnectVerifyInvalidTitle"
        case .scam: return "walletConnectVerifyScamTitle"
        }
    }

    var messageLocalizationKey: String {
        switch validation {
        case .valid: return "walletConnectVerifyValidMessage"
        case .unknown: return "walletConnectVerifyUnknownMessage"
        case .invalid: return "walletConnectVerifyInvalidMessage"
        case .scam: return "walletConnectVerifyScamMessage"
        }
    }

    var isWarning: Bool { validation != .valid }
}

private extension String {
    var isEVMAddressLike: Bool {
        hasPrefix("0x") && count == 42 && dropFirst(2).allSatisfy(\.isHexDigit)
    }
}
