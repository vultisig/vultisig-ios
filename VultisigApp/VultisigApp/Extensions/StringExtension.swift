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
        if hasPrefix("0x") {
            return String(dropFirst(2))
        }
        
        return self
    }
    
    var isZero: Bool {
        return self == .zero
    }
    
    var nilIfEmpty: String? {
        return isEmpty ? nil : self
    }
    func toLibType() -> LibType? {
        if self.uppercased() == "GG20" {
            return LibType.GG20
        } else if self.uppercased() == "DKLS" {
            return LibType.DKLS
        }
        return nil
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
    
    private func getCurrentDecimalPoint() -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current // Ensure it uses system locale
        return formatter.decimalSeparator ?? "."
    }
    
    func formatCurrency() -> String {
        let decimalPoint = getCurrentDecimalPoint()
        return self.replacingOccurrences(of: ",", with: decimalPoint)
    }
    
    func formatCurrencyWithSeparators() -> String {
        guard let number = parseInput() else {
            return self
        }
        
        return number.formatToFiat(includeCurrencySymbol: false, useAbbreviation: false)
    }
    
    func parseInput(locale: Locale = Locale.current) -> Decimal? {
        let usLocale = Locale(identifier: "en_US")
        
        // Attempt 1: Try parsing with "en_US" locale
        let formatterUS = NumberFormatter()
        formatterUS.locale = usLocale
        formatterUS.numberStyle = .decimal
        
        if let number = formatterUS.number(from: self) {
            return number.decimalValue
        }
        
        // Attempt 2: Try parsing with the user's current (or provided default) locale
        // This is only attempted if the US locale parsing failed and the defaultLocale is different from usLocale
        if locale.identifier != usLocale.identifier {
            let formatterCurrent = NumberFormatter()
            formatterCurrent.locale = locale
            formatterCurrent.numberStyle = .decimal
            
            if let number = formatterCurrent.number(from: self) {
                return number.decimalValue
            }
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
