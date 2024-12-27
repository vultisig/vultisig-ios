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
    func formatCurrency() -> String {
        let currency = SettingsCurrency.current
        let decimalPoint = getCurrentDecimalPoint()
        
        if currency.usesEuropeanFormat || decimalPoint == "," {
            return self.replacingOccurrences(of: ",", with: ".")
        } else {
            return self.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ",", with: ".")
        }
    }
    
    func formatCurrencyAbbreviation() -> String {
        let currency = SettingsCurrency.current
        let cleanedValue = self.formatCurrency()
        
        guard let doubleValue = Double(cleanedValue) else {
            return self
        }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        
        if abs(doubleValue) >= 1_000_000_000 {
            let billionValue = doubleValue / 1_000_000_000
            return "\(formatter.string(from: NSNumber(value: billionValue)) ?? "")B"
        } else if abs(doubleValue) >= 1_000_000 {
            let millionValue = doubleValue / 1_000_000
            return "\(formatter.string(from: NSNumber(value: millionValue)) ?? "")M"
        } else {
            return formatter.string(from: NSNumber(value: doubleValue)) ?? self
        }
    }
    
    func formatCurrencyWithSeparators() -> String {
        guard let number = parseInput() else {
            return self
        }
        
        let outputFormatter = NumberFormatter()
        outputFormatter.numberStyle = .decimal
        outputFormatter.minimumFractionDigits = 0
        outputFormatter.maximumFractionDigits = 8
        outputFormatter.decimalSeparator = "."
        outputFormatter.groupingSeparator = ","
        
        return outputFormatter.string(for: number) ?? self
    }
    
    private func parseInput() -> Decimal? {
        let currency = SettingsCurrency.current
        var cleanInput = self.trimmingCharacters(in: .whitespaces)
        
        if currency.usesEuropeanFormat {
            cleanInput = cleanInput.replacingOccurrences(of: ".", with: "")
            cleanInput = cleanInput.replacingOccurrences(of: ",", with: ".")
        } else {
            cleanInput = cleanInput.replacingOccurrences(of: ",", with: "")
        }
        
        return Decimal(string: cleanInput)
    }
    
    private func getCurrentDecimalPoint() -> String {
        let formatter = NumberFormatter()
        return formatter.decimalSeparator ?? "."
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
    
    func isValidDecimal() -> Bool {
        
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.locale = Locale.current // Use the current locale for decimal separator
        
        // Check for both dot and comma as decimal separators
        let dotSeparator = numberFormatter.decimalSeparator == "."
        let modifiedSelf = dotSeparator ? self : self.replacingOccurrences(of: ".", with: ",")
        
        let number = numberFormatter.number(from: modifiedSelf) != nil
        
        return number
        
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
