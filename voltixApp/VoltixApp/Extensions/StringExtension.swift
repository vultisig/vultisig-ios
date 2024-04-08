//
//  StringExtensions.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import SwiftUI

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
        
        if self.hasPrefix("0x") {
            return String(self.dropFirst(2))
        }
        
        return self
    }
    
    func formatCurrency() -> String {
        return self.replacingOccurrences(of: ",", with: ".")
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
}


extension String {
    
    func formatToFiat(includeCurrencySymbol: Bool = true) -> String {
        guard let decimalValue = Decimal(string: self) else { return "" }
        
        let formatter = NumberFormatter()
        
        if includeCurrencySymbol {
            formatter.numberStyle = .currency
            formatter.currencyCode = UserDefaults.standard.string(forKey: "currency") ?? SettingsCurrency.USD.description()
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
}
