//
//  ContractCallExtractor.swift
//  VultisigApp
//

import Foundation

enum ContractCallExtractor {

    struct TokenAndAmount {
        let tokenAddress: String
        let rawAmount: String
    }

    enum ExtractionStrategy {
        // Lending/staking pattern: supply(address asset, uint256 amount, ...)
        // Requires address index < uint256 index to avoid ERC-4626 collisions.
        case firstAddressBeforeFirstUint
        // ERC20 methods called on the token contract itself.
        case contractIsToken
        // Token is the Nth address param (0-indexed).
        case nthAddress(Int)
    }

    /// Decimal string of 2^256 - 1 — the standard max-value sentinel used across DeFi.
    static let maxUInt256Decimal = "115792089237316195423570985008687907853269984665640564039457584007913129639935"

    // Functions where MAX_UINT256 means "unlimited approval" — the only case where
    // a sentinel label makes sense. decreaseAllowance is excluded because
    // decreaseAllowance(MAX_UINT256) reduces allowance by that amount, it does
    // not grant an unlimited approval. For withdraw/repay MAX_UINT256 means
    // "all available" but the exact amount depends on on-chain state, so we
    // return nil and let the caller skip the amount display.
    private static let unlimitedApprovalFunctions: Set<String> = [
        "approve", "increaseAllowance",
        "permit", "permitSingle", "permitBatch"
    ]

    /// If `funcName` uses MAX_UINT256 as an "unlimited approval" sentinel, returns
    /// the localized "Unlimited" label. For all other functions returns `nil` — the
    /// caller should omit the amount rather than display a vague label.
    static func sentinelLabelFor(funcName: String) -> String? {
        unlimitedApprovalFunctions.contains(funcName) ? "unlimited".localized : nil
    }

    /// Extract the function name from an ABI signature like "withdraw(address,uint256,address)".
    static func evmFunctionName(from signature: String) -> String? {
        guard let parenIndex = signature.firstIndex(of: "(") else { return nil }
        let name = String(signature[..<parenIndex]).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private static let registry: [String: ExtractionStrategy] = [
        // Aave V3 / Spark / Radiant
        "supply": .firstAddressBeforeFirstUint,
        "supplyWithPermit": .firstAddressBeforeFirstUint,
        "withdraw": .firstAddressBeforeFirstUint,
        "borrow": .firstAddressBeforeFirstUint,
        "repay": .firstAddressBeforeFirstUint,
        "repayWithPermit": .firstAddressBeforeFirstUint,
        "repayWithATokens": .firstAddressBeforeFirstUint,
        // Compound V3
        "supplyTo": .nthAddress(1),
        "withdrawTo": .nthAddress(1),
        "transferAsset": .nthAddress(1),
        // EigenLayer
        "depositIntoStrategy": .nthAddress(1),
        "depositIntoStrategyWithSignature": .nthAddress(1),
        // Across Protocol V3
        "depositV3": .nthAddress(2),
        // ERC20 methods on the token contract itself
        "transfer": .contractIsToken,
        "transferFrom": .contractIsToken,
        "approve": .contractIsToken,
        "increaseAllowance": .contractIsToken,
        "decreaseAllowance": .contractIsToken
    ]

    static func extract(
        signature: String,
        argsJson: String,
        toAddress: String?
    ) -> TokenAndAmount? {
        guard let parenStart = signature.firstIndex(of: "("),
              let parenEnd = signature.lastIndex(of: ")")
        else { return nil }

        let funcName = String(signature[..<parenStart]).trimmingCharacters(in: .whitespaces)
        guard let strategy = registry[funcName] else { return nil }

        let paramsString = String(signature[signature.index(after: parenStart)..<parenEnd])
        let paramTypes = splitTopLevel(paramsString)

        guard let argsData = argsJson.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: argsData) as? [String]
        else { return nil }

        guard let uint256Idx = paramTypes.firstIndex(of: "uint256"),
              uint256Idx < args.count
        else { return nil }
        let rawAmount = args[uint256Idx]
        guard !rawAmount.isEmpty,
              rawAmount.allSatisfy({ $0.isNumber })
        else { return nil }

        switch strategy {
        case .contractIsToken:
            guard let toAddress, !toAddress.isEmpty else { return nil }
            return TokenAndAmount(tokenAddress: toAddress, rawAmount: rawAmount)

        case .firstAddressBeforeFirstUint:
            guard let addressIdx = paramTypes.firstIndex(of: "address"),
                  addressIdx < uint256Idx,
                  addressIdx < args.count
            else { return nil }
            let tokenAddress = args[addressIdx]
            guard !tokenAddress.isEmpty else { return nil }
            return TokenAndAmount(tokenAddress: tokenAddress, rawAmount: rawAmount)

        case .nthAddress(let n):
            var count = 0
            var targetIdx = -1
            for (i, type) in paramTypes.enumerated() where type == "address" {
                if count == n {
                    targetIdx = i
                    break
                }
                count += 1
            }
            guard targetIdx != -1, targetIdx < args.count else { return nil }
            let tokenAddress = args[targetIdx]
            guard !tokenAddress.isEmpty else { return nil }
            return TokenAndAmount(tokenAddress: tokenAddress, rawAmount: rawAmount)
        }
    }

    // Split a param list on top-level commas only, respecting nested parentheses
    // so tuple types like `(uint256,uint256)` stay intact as one param.
    private static func splitTopLevel(_ params: String) -> [String] {
        var parts: [String] = []
        var depth = 0
        var current = ""
        for ch in params {
            if ch == "(" {
                depth += 1
            } else if ch == ")" {
                depth -= 1
            }
            if ch == "," && depth == 0 {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            parts.append(current.trimmingCharacters(in: .whitespaces))
        }
        return parts
    }
}
