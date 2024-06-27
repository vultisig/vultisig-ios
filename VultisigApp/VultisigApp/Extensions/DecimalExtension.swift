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

    init(_ bigInt: BigInt) {
        self = .init(string: bigInt.description) ?? 0
    }
}

