//
//  DecimalExtension.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 08/04/2024.
//

import Foundation
import Foundation
import SwiftUI
import BigInt

extension Decimal {
    
    func truncated(toPlaces places: Int) -> Decimal {
        var original = self
        var truncated = Decimal()
        NSDecimalRound(&truncated, &original, places, .down)
        return truncated
    }
    
    func formatToFiat(includeCurrencySymbol: Bool = true) -> String {
        let formatter = NumberFormatter()
        if includeCurrencySymbol {
            formatter.numberStyle = .currency
            formatter.currencyCode = SettingsCurrency.current.rawValue
        } else {
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
            formatter.decimalSeparator = "."
            formatter.groupingSeparator = ","
        }
        
        let abbrevation = getAbbrevationValues()
        let value = abbrevation.value
        let prefix = abbrevation.prefix
        
        // Convert Decimal to NSDecimalNumber before using with NumberFormatter
        let number = NSDecimalNumber(decimal: value)
        return (formatter.string(from: number) ?? "") + prefix
    }
    
    func formatToDecimal(digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = digits
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = ""
        formatter.decimalSeparator = "."
        
        let abbrevation = getAbbrevationValues()
        let value = abbrevation.value
        let prefix = abbrevation.prefix
        
        // Convert Decimal to NSDecimalNumber before using with NumberFormatter
        let number = NSDecimalNumber(decimal: value)
        
        return (formatter.string(from: number) ?? "") + prefix
    }
    
    private func getAbbrevationValues() -> (value: Decimal, prefix: String) {
        let millionValue: Decimal = 1_000_000
        let billionValue: Decimal = 1_000_000_000
        
        let value: Decimal
        let prefix: String
        
        if self > billionValue {
            value = self/billionValue
            prefix = "B"
        } else if self > millionValue {
            value = self/millionValue
            prefix = "M"
        } else {
            value = self
            prefix = ""
        }
        
        return (value: value, prefix: prefix)
    }

    init(_ bigInt: BigInt) {
        self = .init(string: bigInt.description) ?? 0
    }
}

