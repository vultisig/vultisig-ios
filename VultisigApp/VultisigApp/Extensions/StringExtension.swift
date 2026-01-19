//
//  StringExtensions.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import SwiftUI
import BigInt

// MARK: - String Extensions for Padding and Hex Processing

extension String {
    func paddingLeft(toLength: Int, withPad character: String) -> String {
        let toPad = toLength - self.count
        
        if toPad < 1 {
            return self
        }
        
        return "".padding(toLength: toPad, withPad: character, startingAt: 0) + self
    }
    
    func stripHexPrefix() -> String {
        return hasPrefix("0x") ? String(dropFirst(2)) : self
    }
    
    var add0x: String {
        hasPrefix("0x") ? self : "0x" + self
    }
    
    var isZero: Bool {
        return self == .zero
    }
    
    var nilIfEmpty: String? {
        return isEmpty ? nil : self
    }
    func toLibType() -> LibType? {
        LibType.allCases.first {
            $0.toString().uppercased() == self.uppercased()
        }
    }
    
    var isNotEmpty: Bool {
        !isEmpty
    }
    
    static let hideBalanceText = Array.init(repeating: "•", count: 8).joined(separator: " ")
    
    var truncatedAddress: String {
        self.prefix(4) + "..." + self.suffix(4)
    }
}

// MARK: - String constants

extension String {
    
    static var empty: String {
        return ""
    }
    
    static var newline: String {
        return "\n"
    }
    
    static var space: String {
        return " "
    }
    
    static var zero: String {
        return "0"
    }
}

// MARK: - Amount Formatter
extension String {
    func parseInput(locale: Locale = Locale.current) -> Decimal? {
        let usLocale = Locale(identifier: "en_US")
        
        // Attempt 1: Try parsing with the user's current (or provided default) locale first
        // This ensures comma-based locales (Europe/Brazil) work correctly
        if locale.identifier != usLocale.identifier {
            let formatterCurrent = NumberFormatter()
            formatterCurrent.locale = locale
            formatterCurrent.numberStyle = .decimal
            
            if let number = formatterCurrent.number(from: self) {
                return number.decimalValue
            }
        }
        
        // Attempt 2: Fallback to parsing with "en_US" locale
        let formatterUS = NumberFormatter()
        formatterUS.locale = usLocale
        formatterUS.numberStyle = .decimal
        
        if let number = formatterUS.number(from: self) {
            return number.decimalValue
        }
        
        // If both attempts fail
        return nil
    }
}

extension String {
    func toDecimal() -> Decimal {
        if self.isEmpty {
            return .zero
        }
        guard let number = parseInput() else {
            print("Failed to convert to Decimal: \(self)")
            return .zero
        }
        
        return number
    }
    
    func formatToFiat(includeCurrencySymbol: Bool = true) -> String {
        guard let number = parseInput() else {
            return self
        }
        
        return number.formatToFiat(includeCurrencySymbol: includeCurrencySymbol, useAbbreviation: false)
    }
    
    func formatToDecimal(digits: Int = 8) -> String {
        guard let number = parseInput() else {
            return self
        }
        
        return number.formatToDecimal(digits: digits)
    }
    
    func toBigInt() -> BigInt {
        guard let valueBigInt = BigInt(self) else {
            return BigInt.zero
        }
        return valueBigInt
    }
    
    // We must truncate before converting to bigInt.
    func toBigInt(decimals: Int) -> BigInt {
        self.toDecimal().truncated(toPlaces: decimals).description.toBigInt()
    }
    
    func isValidDecimal() -> Bool {
        guard let number = parseInput() else {
            return false
        }
        
        return number >= 0
    }
    
    var isValidEmail: Bool {
        let regex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let predicate = NSPredicate(format:"SELF MATCHES %@", regex)
        return predicate.evaluate(with: self)
    }
}

extension String {
    func toFormattedTitleCase() -> String {
        let formattedString = self
            .enumerated()
            .map { index, character in
                if index > 0 && character.isUppercase {
                    return " \(character)"
                } else {
                    return String(character)
                }
            }
            .joined()
            .capitalized
        return formattedString
    }
}

// Used only for ENS Names Eg.: vitalik.eth
extension String {
    func namehash() -> String {
        // Split the ENS name into labels
        let labels = self.split(separator: ".").reversed()
        
        // Initialize the node as 32 bytes of zero data
        var node: Data = Data(repeating: 0, count: 32)
        
        for label in labels {
            // Convert the label to Data, hash it, and get the hex representation
            let labelData = Data(label.utf8)
            let labelHash = labelData.sha3(.keccak256)
            
            // Combine the current node hash with the label hash and hash again
            node = (node + labelHash).sha3(.keccak256)
        }
        
        // Convert the final node to a hex string
        return "0x" + node.toHexString()
    }
    
    func isENSNameService() -> Bool {
        let domains = [".eth", ".sol"]
        return domains.contains(where: { self.contains($0) })
    }
    
    static var zeroAddress: String {
        return "0x0000000000000000000000000000000000000000"
    }
    
    static var anyAddress: String {
        return "0x1111111111111111111111111111111111111111"
    }
}

extension String {
    var localized: String {
        NSLocalizedString(self, comment: "")
    }

    var truncatedMiddle: String {
        guard count > 10 else { return self }
        return "\(self.prefix(4))...\(self.suffix(4))"
    }
}

// MARK: - Base64 Encoding/Decoding
extension String {
    /// Converts a base64-encoded string to Data (byte array)
    /// Equivalent to CosmJS's fromBase64 function
    /// - Returns: Data if decoding succeeds, nil otherwise
    func fromBase64() -> Data? {
        return Data(base64Encoded: self)
    }

    /// Converts a base64-encoded string to a byte array ([UInt8])
    /// - Returns: Array of bytes if decoding succeeds, nil otherwise
    func fromBase64Bytes() -> [UInt8]? {
        guard let data = fromBase64() else { return nil }
        return Array(data)
    }
}
