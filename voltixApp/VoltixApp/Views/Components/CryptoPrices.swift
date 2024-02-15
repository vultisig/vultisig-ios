//
//  CryptoPrices.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 14/02/2024.
//

import Foundation
import SwiftUI

struct CryptoPricesView: View {
    @StateObject private var viewModel = CryptoPriceViewModel()
    
    var body: some View {
        VStack {
            if let cryptoPrices = viewModel.cryptoPrices {
                ForEach(cryptoPrices.prices.keys.sorted(), id: \.self) { key in
                    if let prices = cryptoPrices.prices[key] {
                        Text("\(key.capitalized) Prices:")
                        ForEach(prices.keys.sorted(), id: \.self) { currency in
                            Text("\(currency.uppercased()): \(prices[currency]!, specifier: "%.2f")")
                        }
                    }
                }
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            }
            
            Button("Fetch Bitcoin Prices") {
                Task {
                    await viewModel.fetchCryptoPrices(for: "bitcoin", for: "usd")
                }
            }
        }
    }
}

#Preview {
    CryptoPricesView()
}
