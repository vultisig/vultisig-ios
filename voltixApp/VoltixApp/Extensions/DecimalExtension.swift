//
//  DecimalExtension.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 08/04/2024.
//

import Foundation
import Foundation
import SwiftUI

extension Decimal {
    
    func formatToFiat(includeCurrencySymbol: Bool = true) -> String {
        
        let formatter = NumberFormatter()
        
        if includeCurrencySymbol {
            formatter.numberStyle = .currency
            formatter.currencyCode = UserPreferencesStore.currency ?? SettingsCurrency.USD.description()
        } else {
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
            formatter.decimalSeparator = "."
            formatter.groupingSeparator = ""
        }
        
        // Convert Decimal to NSDecimalNumber before using with NumberFormatter
        let number = NSDecimalNumber(decimal: self)
        
        return formatter.string(from: number) ?? ""
    }
    
    func formatToDecimal(digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = digits
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = ""
        formatter.decimalSeparator = "."
        
        // Convert Decimal to NSDecimalNumber before using with NumberFormatter
        let number = NSDecimalNumber(decimal: self)
        
        return formatter.string(from: number) ?? ""
    }
}

