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
    
    /// Base method for formatting fiat values with configurable decimal places
    private func formatToFiat(includeCurrencySymbol: Bool = true, useAbbreviation: Bool = false, maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        if includeCurrencySymbol {
            formatter.numberStyle = .currency
            formatter.currencyCode = SettingsCurrency.current.rawValue
        } else {
            formatter.numberStyle = .decimal
        }
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = 2
        formatter.decimalSeparator = Locale.current.decimalSeparator ?? "."
        formatter.groupingSeparator = Locale.current.groupingSeparator ?? ","
        formatter.roundingMode = .down
        
        let number = NSDecimalNumber(decimal: self)
        return formatter.string(from: number) ?? ""
    }
    
    /// Format fiat value with standard 2 decimal places
    func formatToFiat(includeCurrencySymbol: Bool = true, useAbbreviation: Bool = false) -> String {
        return formatToFiat(includeCurrencySymbol: includeCurrencySymbol, useAbbreviation: useAbbreviation, maximumFractionDigits: 2)
    }
    
    /// Format fiat value for fee display with more decimal places to show small fees
    func formatToFiatForFee(includeCurrencySymbol: Bool = true) -> String {
        return formatToFiat(includeCurrencySymbol: includeCurrencySymbol, useAbbreviation: false, maximumFractionDigits: 5)
    }
    
    func formatDecimalToLocale(locale: Locale = Locale.current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 0
        formatter.roundingMode = .down
        return formatter.string(from: self as NSDecimalNumber) ?? ""
    }
    
    /// Format large numbers with abbreviations (M, B, T) for DISPLAY ONLY
    /// ⚠️ NEVER use in input fields - only for displaying values
    func formatWithAbbreviation(maxDecimals: Int = 2) -> String {
        let absValue = abs(self)
        let isNegative = self < 0
        let prefix = isNegative ? "-" : ""
        
        let trillion = Decimal(1_000_000_000_000)
        let billion = Decimal(1_000_000_000)
        let million = Decimal(1_000_000)
        let thousand = Decimal(1_000)
        
        if absValue >= trillion {
            let value = (absValue / trillion).truncated(toPlaces: maxDecimals)
            return "\(prefix)\(value.formatToDecimal(digits: maxDecimals))T"
        } else if absValue >= billion {
            let value = (absValue / billion).truncated(toPlaces: maxDecimals)
            return "\(prefix)\(value.formatToDecimal(digits: maxDecimals))B"
        } else if absValue >= million {
            let value = (absValue / million).truncated(toPlaces: maxDecimals)
            return "\(prefix)\(value.formatToDecimal(digits: maxDecimals))M"
        } else if absValue >= thousand {
            let value = (absValue / thousand).truncated(toPlaces: maxDecimals)
            return "\(prefix)\(value.formatToDecimal(digits: maxDecimals))K"
        } else {
            return "\(prefix)\(absValue.formatToDecimal(digits: maxDecimals))"
        }
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
    
    /// Format values ​​for display, automatically using abbreviations for large values
    /// For values ​​>= 1M, use abbreviations (K, M, B, T)
    /// For values ​​< 1M, use standard decimal formatting with locale
    /// ⚠️ ONLY for display - never use in input fields
    func formatForDisplay(maxDecimals: Int = 2, locale: Locale = Locale.current, skipAbbreviation: Bool = false) -> String {
        let million = Decimal(1_000_000)
        
        if abs(self) >= million, !skipAbbreviation {
            return formatWithAbbreviation(maxDecimals: maxDecimals)
        } else {
            return formatDecimalToLocale(locale: locale)
        }
    }
    
    init(_ bigInt: BigInt) {
        self = .init(string: bigInt.description) ?? 0
    }
    
    func toInt() -> Int {
        return NSDecimalNumber(decimal: self).intValue
    }
}
