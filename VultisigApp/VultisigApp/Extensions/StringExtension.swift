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
    
    func formatCurrency() -> String {
        return self.replacingOccurrences(of: ",", with: ".")
    }
    
    var isZero: Bool {
        return self == .zero
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


extension String {
    
    func toDecimal() -> Decimal {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.replacingOccurrences(of: ",", with: "")
        
        if let decimal = Decimal(string: cleaned) {
            return decimal
        } else {
            print("Failed to convert to Decimal: \(self)")
            return .zero
        }
    }
    
    func fiatToDecimal() -> Decimal? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = SettingsCurrency.current.rawValue
        
        let cleanString = self
            .replacingOccurrences(of: formatter.currencySymbol, with: "")
            .replacingOccurrences(of: formatter.groupingSeparator, with: "")
            .replacingOccurrences(of: formatter.decimalSeparator, with: ".")
            .trimmingCharacters(in: .whitespaces)
        
        return Decimal(string: cleanString)
    }
    
    func formatToFiat(includeCurrencySymbol: Bool = true) -> String {
        guard let decimalValue = Decimal(string: self) else { return "" }
        
        let formatter = NumberFormatter()
        
        if includeCurrencySymbol {
            formatter.numberStyle = .currency
            formatter.currencyCode = SettingsCurrency.current.rawValue
        } else {
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
            formatter.decimalSeparator = "."
            formatter.groupingSeparator = ""
        }
        
        let number = NSDecimalNumber(decimal: decimalValue)
        return formatter.string(from: number) ?? ""
    }
    
    func formatToDecimal(digits: Int) -> String {
        guard let decimalValue = Decimal(string: self) else { return "" }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = digits
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = ""
        formatter.decimalSeparator = "."
        
        let number = NSDecimalNumber(decimal: decimalValue)
        return formatter.string(from: number) ?? ""
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
