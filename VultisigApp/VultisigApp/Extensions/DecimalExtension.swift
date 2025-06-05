//
//  DecimalExtension.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 08/04/2024.
//

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
    
    func formatToFiat(includeCurrencySymbol: Bool = true, useAbbreviation: Bool = false) -> String {
        let formatter = NumberFormatter()
        if includeCurrencySymbol {
            formatter.numberStyle = .currency
            formatter.currencyCode = SettingsCurrency.current.rawValue
        } else {
            formatter.numberStyle = .decimal
        }
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.decimalSeparator = Locale.current.decimalSeparator ?? "."
        formatter.groupingSeparator = Locale.current.groupingSeparator ?? ","
        formatter.roundingMode = .down
        
        let number = NSDecimalNumber(decimal: self)
        return formatter.string(from: number) ?? ""
    }
    
    func formatDecimalToLocale(locale: Locale = Locale.current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 4
        formatter.roundingMode = .down
        return formatter.string(from: self as NSDecimalNumber) ?? ""
    }
    
    func formatToDecimal(digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = digits
        formatter.minimumFractionDigits = 0
        formatter.decimalSeparator = Locale.current.decimalSeparator ?? "."
        formatter.groupingSeparator = Locale.current.groupingSeparator ?? ","
        formatter.roundingMode = .down
        
        // Convert Decimal to NSDecimalNumber before using with NumberFormatter
        let number = NSDecimalNumber(decimal: self)
        
        return formatter.string(from: number) ?? ""
    }
    
    init(_ bigInt: BigInt) {
        self = .init(string: bigInt.description) ?? 0
    }
}

