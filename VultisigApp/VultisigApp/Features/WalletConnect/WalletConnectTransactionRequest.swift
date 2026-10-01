//
//  WalletConnectTransactionRequest.swift
//  VultisigApp
//

import BigInt
import Foundation

struct WalletConnectTransactionRequest: Identifiable, Equatable {
    var id: String { requestId.stringValue }

    let topic: String
    let requestId: WalletConnectRequestID
    let method: String
    let chain: Chain
    let from: String
    let to: String
    let valueWei: BigInt
    let valueAmount: String
    let data: String
    let requestedOverrides: WalletConnectTransactionOverrides
    let vaultPubKeyECDSA: String
    let vaultLocalPartyID: String
    let dappMetadata: DAppMetadata
    let verifyContext: WalletConnectVerifyContext?
    let transaction: SendTransaction
}

struct WalletConnectTransactionOverrides: Equatable {
    let gas: BigInt?
    let gasPrice: BigInt?
    let maxFeePerGas: BigInt?
    let maxPriorityFeePerGas: BigInt?
    let nonce: BigInt?

    var unsupportedFields: [String] { [] }

    var displayFields: [(String, BigInt)] {
        var fields: [(String, BigInt)] = []
        if let gas { fields.append(("gas", gas)) }
        if let gasPrice { fields.append(("gasPrice", gasPrice)) }
        if let maxFeePerGas { fields.append(("maxFeePerGas", maxFeePerGas)) }
        if let maxPriorityFeePerGas { fields.append(("maxPriorityFeePerGas", maxPriorityFeePerGas)) }
        if let nonce { fields.append(("nonce", nonce)) }
        return fields
    }

    func applying(to chainSpecific: BlockChainSpecific) throws -> BlockChainSpecific {
        guard case let .Ethereum(currentMaxFeePerGas, currentPriorityFee, currentNonce, currentGasLimit) = chainSpecific else {
            return chainSpecific
        }
        let resolvedMaxFeePerGas = maxFeePerGas ?? gasPrice ?? currentMaxFeePerGas
        let resolvedPriorityFee = maxPriorityFeePerGas ?? (gasPrice == nil ? currentPriorityFee : .zero)
        guard resolvedPriorityFee <= resolvedMaxFeePerGas else {
            throw WalletConnectTransactionRequestError.invalidParams("maxPriorityFeePerGas must not exceed maxFeePerGas")
        }
        let resolvedNonce: Int64
        if let nonce {
            guard nonce <= BigInt(Int64.max), let intNonce = Int64(nonce.description) else {
                throw WalletConnectTransactionRequestError.invalidParams("nonce is too large")
            }
            resolvedNonce = intNonce
        } else {
            resolvedNonce = currentNonce
        }
        return .Ethereum(
            maxFeePerGasWei: resolvedMaxFeePerGas,
            priorityFeeWei: resolvedPriorityFee,
            nonce: resolvedNonce,
            gasLimit: gas ?? currentGasLimit
        )
    }
}

struct WalletConnectParsedTransactionRequest: Equatable {
    let method: String
    let caip2ChainId: String?
    let from: String
    let to: String?
    let valueWei: BigInt
    let data: String
    let overrides: WalletConnectTransactionOverrides
}

enum WalletConnectTransactionRequestError: LocalizedError, Equatable {
    case unsupportedMethod(String)
    case invalidParams(String)
    case missingChainId
    case unsupportedChain(String)
    case missingBoundVault(String)
    case missingBoundAccount(String)
    case missingNativeCoin(String)
    case unsupportedOverride(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedMethod(let method):
            return String(format: "walletConnectTransactionErrorUnsupportedMethod".localized, method)
        case .invalidParams(let reason):
            return String(format: "walletConnectTransactionErrorInvalidParams".localized, reason)
        case .missingChainId:
            return "walletConnectTransactionErrorMissingChainId".localized
        case .unsupportedChain(let chainId):
            return String(format: "walletConnectTransactionErrorUnsupportedChain".localized, chainId)
        case .missingBoundVault:
            return "walletConnectTransactionErrorMissingBoundVault".localized
        case .missingBoundAccount:
            return "walletConnectTransactionErrorMissingBoundAccount".localized
        case .missingNativeCoin(let chain):
            return String(format: "walletConnectTransactionErrorMissingNativeCoin".localized, chain)
        case .unsupportedOverride(let fields):
            return String(format: "walletConnectTransactionErrorUnsupportedOverride".localized, fields)
        }
    }
}

struct WalletConnectTransactionRequestParser {
    func parse(_ request: WalletConnectIncomingRequest) throws -> WalletConnectParsedTransactionRequest {
        guard request.method == "eth_sendTransaction" else {
            throw WalletConnectTransactionRequestError.unsupportedMethod(request.method)
        }
        let values = try parseArray(request.paramsJSON)
        guard let object = values.first as? [String: Any] else {
            throw WalletConnectTransactionRequestError.invalidParams("eth_sendTransaction requires a transaction object")
        }
        let from = try addressValue(object["from"], label: "from")
        let to = try optionalAddressValue(object["to"], label: "to")
        let data = try calldataValue(object["data"] ?? object["input"])
        let valueWei = try quantityValue(object["value"], label: "value") ?? .zero
        let overrides = WalletConnectTransactionOverrides(
            gas: try quantityValue(object["gas"], label: "gas"),
            gasPrice: try quantityValue(object["gasPrice"], label: "gasPrice"),
            maxFeePerGas: try quantityValue(object["maxFeePerGas"], label: "maxFeePerGas"),
            maxPriorityFeePerGas: try quantityValue(object["maxPriorityFeePerGas"], label: "maxPriorityFeePerGas"),
            nonce: try quantityValue(object["nonce"], label: "nonce")
        )
        return WalletConnectParsedTransactionRequest(
            method: request.method,
            caip2ChainId: request.chainId,
            from: from,
            to: to,
            valueWei: valueWei,
            data: data,
            overrides: overrides
        )
    }

    private func parseArray(_ json: String) throws -> [Any] {
        guard let data = json.data(using: .utf8) else {
            throw WalletConnectTransactionRequestError.invalidParams("params are not UTF-8")
        }
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let array = object as? [Any] else {
            throw WalletConnectTransactionRequestError.invalidParams("params must be a JSON array")
        }
        return array
    }

    private func addressValue(_ value: Any?, label: String) throws -> String {
        guard let address = value as? String, address.walletConnectIsEVMAddress else {
            throw WalletConnectTransactionRequestError.invalidParams("\(label) must be an EVM address")
        }
        return address
    }

    private func optionalAddressValue(_ value: Any?, label: String) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        return try addressValue(value, label: label)
    }

    private func calldataValue(_ value: Any?) throws -> String {
        guard let value, !(value is NSNull) else { return "" }
        guard let data = value as? String else {
            throw WalletConnectTransactionRequestError.invalidParams("data must be a hex string")
        }
        guard data.walletConnectIsHexData else {
            throw WalletConnectTransactionRequestError.invalidParams("data must be 0x-prefixed hex")
        }
        return data == "0x" ? "" : data.lowercased()
    }

    private func quantityValue(_ value: Any?, label: String) throws -> BigInt? {
        guard let value, !(value is NSNull) else { return nil }
        guard let quantity = value as? String else {
            throw WalletConnectTransactionRequestError.invalidParams("\(label) must be a hex quantity")
        }
        guard quantity.hasPrefix("0x"), quantity.count > 2 else {
            throw WalletConnectTransactionRequestError.invalidParams("\(label) must be a non-empty hex quantity")
        }
        let raw = String(quantity.dropFirst(2))
        guard raw.allSatisfy(\.isHexDigit), let parsed = BigInt(raw, radix: 16), parsed >= .zero else {
            throw WalletConnectTransactionRequestError.invalidParams("\(label) must be a valid hex quantity")
        }
        guard raw == "0" || !raw.hasPrefix("0") else {
            throw WalletConnectTransactionRequestError.invalidParams("\(label) must be a minimal hex quantity")
        }
        return parsed
    }
}

extension KeysignPayload {
    func applyingWalletConnectOverrides(_ overrides: WalletConnectTransactionOverrides) throws -> KeysignPayload {
        try withChainSpecific(overrides.applying(to: chainSpecific))
    }
}

struct WalletConnectTransactionRequestBuilder {
    private let parser = WalletConnectTransactionRequestParser()
    private let chainResolver = WalletConnectTransactionChainResolver()

    func build(
        incoming request: WalletConnectIncomingRequest,
        binding: WalletConnectSessionBinding?,
        vaults: [Vault]
    ) throws -> WalletConnectTransactionRequest {
        let parsed = try parser.parse(request)
        let chain = try chainResolver.resolve(parsed.caip2ChainId)
        guard parsed.to != nil else {
            throw WalletConnectTransactionRequestError.invalidParams("contract creation is not supported")
        }
        let unsupportedOverrides = parsed.overrides.unsupportedFields
        guard unsupportedOverrides.isEmpty else {
            throw WalletConnectTransactionRequestError.unsupportedOverride(unsupportedOverrides.joined(separator: ", "))
        }
        guard let binding else {
            throw WalletConnectTransactionRequestError.missingBoundVault(request.topic)
        }
        guard let vault = vaults.first(where: { $0.pubKeyECDSA == binding.vaultPubKeyECDSA }) else {
            throw WalletConnectTransactionRequestError.missingBoundVault(request.topic)
        }
        guard vault.walletConnectEVMAccounts.contains(where: {
            $0.chainReference == parsed.caip2ChainId && $0.address.caseInsensitiveCompare(parsed.from) == .orderedSame
        }) else {
            throw WalletConnectTransactionRequestError.missingBoundAccount(parsed.from)
        }
        guard let coin = vault.coins.first(where: { $0.chain == chain && $0.isNativeToken }) else {
            throw WalletConnectTransactionRequestError.missingNativeCoin(chain.name)
        }
        let valueAmount = Self.amountString(wei: parsed.valueWei, decimals: coin.decimals)
        let tx = SendTransaction(
            coin: coin,
            vault: vault,
            fromAddress: parsed.from,
            toAddress: parsed.to ?? "",
            toAddressLabel: nil,
            amount: valueAmount,
            amountInFiat: "",
            memo: parsed.data,
            gas: .zero,
            fee: .zero,
            feeMode: .default,
            estimatedGasLimit: parsed.overrides.gas,
            customGasLimit: parsed.overrides.gas,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: coin
        )
        return WalletConnectTransactionRequest(
            topic: request.topic,
            requestId: request.requestId,
            method: parsed.method,
            chain: chain,
            from: parsed.from,
            to: parsed.to ?? "",
            valueWei: parsed.valueWei,
            valueAmount: valueAmount,
            data: parsed.data,
            requestedOverrides: parsed.overrides,
            vaultPubKeyECDSA: vault.pubKeyECDSA,
            vaultLocalPartyID: vault.localPartyID,
            dappMetadata: DAppMetadata(name: request.dappName, url: request.dappURL, iconURL: request.dappIcon ?? ""),
            verifyContext: request.verifyContext,
            transaction: tx
        )
    }

    static func amountString(wei: BigInt, decimals: Int) -> String {
        guard wei > .zero else { return "0" }
        let divisor = BigInt(10).power(decimals)
        let whole = wei / divisor
        let fraction = wei % divisor
        guard fraction > .zero else { return whole.description }
        var padded = String(repeating: "0", count: decimals - fraction.description.count) + fraction.description
        while padded.last == "0" {
            padded.removeLast()
        }
        return "\(whole).\(padded)"
    }
}

struct WalletConnectTransactionChainResolver {
    func resolve(_ caip2ChainId: String?) throws -> Chain {
        do {
            return try WalletConnectEVMChainResolver().resolve(caip2ChainId)
        } catch let error as WalletConnectMessageRequestError {
            switch error {
            case .missingChainId:
                throw WalletConnectTransactionRequestError.missingChainId
            case .unsupportedChain(let chainId):
                throw WalletConnectTransactionRequestError.unsupportedChain(chainId)
            default:
                throw error
            }
        }
    }
}

extension WalletConnectTransactionOverrides {
    func feeDisplayValue(ticker: String) -> String {
        if let maxFeePerGas {
            return "maxFeePerGas: \(maxFeePerGas) wei"
        }
        if let gasPrice {
            return "gasPrice: \(gasPrice) wei"
        }
        return String(format: "walletConnectTransactionEstimatedFeeValue".localized, ticker)
    }
}

extension String {
    var walletConnectIsEVMAddress: Bool {
        hasPrefix("0x") && count == 42 && dropFirst(2).allSatisfy(\.isHexDigit)
    }

    var walletConnectIsHexData: Bool {
        hasPrefix("0x") && dropFirst(2).allSatisfy(\.isHexDigit) && dropFirst(2).count.isMultiple(of: 2)
    }

    var walletConnectShortAddress: String {
        guard count > 12 else { return self }
        return "\(prefix(6))…\(suffix(4))"
    }
}
