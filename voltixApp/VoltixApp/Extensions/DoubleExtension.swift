//
//  DoubleExtension.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 08/04/2024.
//

import Foundation
import Foundation
import SwiftUI

extension Double {
    
    func formatToFiatxxx(includeCurrencySymbol: Bool = true) -> String {
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
        
        return formatter.string(from: NSNumber(value: self)) ?? .empty
    }
}
