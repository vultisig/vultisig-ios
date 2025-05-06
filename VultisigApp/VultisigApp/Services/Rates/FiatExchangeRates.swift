//
//  FiatExchangeRates.swift
//  VultisigApp
//
//  Created on 2025-05-06.
//

import Foundation
import VultisigApp // For Endpoint

/// Manages fiat-to-fiat exchange rates using USDC as the common reference point
class FiatExchangeRates {
    
    static let shared = FiatExchangeRates()
    
    // Flag to prevent multiple simultaneous update calls
    private var isUpdating = false
    
    // UserDefaults keys for caching
    private let ratesKey = "FiatExchangeRates.rates"
    private let lastUpdateKey = "FiatExchangeRates.lastUpdate"
    
    private init() {
        loadCachedRates()
    }
    
    /// Maps fiat currency codes to their USDC exchange rate
    /// Key: fiat currency code (lowercase), Value: 1 USDC = X units of the fiat
    private var exchangeRates: [String: Double] = [:]
    private var lastUpdateTime: Date?
    
    /// Timeout for refreshing exchange rates (10 minutes)
    private let rateRefreshInterval: TimeInterval = 10 * 60
    
    /// Checks if exchange rates need updating
    var needsUpdate: Bool {
        guard let lastUpdate = lastUpdateTime else {
            return true
        }
        return Date().timeIntervalSince(lastUpdate) > rateRefreshInterval
    }
    
    /// Load cached exchange rates from UserDefaults
    private func loadCachedRates() {
        if let savedRates = UserDefaults.standard.dictionary(forKey: ratesKey) as? [String: Double],
           let savedTime = UserDefaults.standard.object(forKey: lastUpdateKey) as? Date {
            self.exchangeRates = savedRates
            self.lastUpdateTime = savedTime
            // Loaded cached exchange rates from storage
        }
    }
    
    /// Save exchange rates to UserDefaults
    private func saveRatesToCache() {
        UserDefaults.standard.set(exchangeRates, forKey: ratesKey)
        UserDefaults.standard.set(lastUpdateTime, forKey: lastUpdateKey)
    }
    
    /// Update exchange rates using USDC as the reference point
    /// - Returns: True if rates were successfully updated
    func updateExchangeRates() async -> Bool {
        // Prevent multiple simultaneous update calls
        guard !isUpdating else {
            // Exchange rate update already in progress
            return false
        }
        
        // If we already have fresh rates, return true without fetching
        if !needsUpdate && !exchangeRates.isEmpty {
            // Using cached exchange rates
            return true
        }
        
        isUpdating = true
        defer { isUpdating = false }
        
        do {
            // Use USDC as the reference for fiat-to-fiat rates
            let usdcId = "usd-coin" // CoinGecko ID for USDC
            
            // List of common fiat currencies to support
            // Derived from SettingsCurrency enum to avoid duplication
            let commonFiatCurrencies = SettingsCurrency.allCases.map { $0.rawValue.lowercased() }
            let fiatCurrencies = commonFiatCurrencies.joined(separator: ",")
            
            let endpoint = Endpoint.fetchCryptoPrices(ids: usdcId, currencies: fiatCurrencies)
            // Fetching fiat exchange rates for USDC
            
            let (data, _) = try await URLSession.shared.data(from: endpoint)
            let response = try JSONDecoder().decode([String: [String: Double]].self, from: data)
            
            guard let usdcRates = response[usdcId] else {
                // Failed to get USDC rates
                return false
            }
            
            // Update our exchange rates
            exchangeRates = usdcRates
            lastUpdateTime = Date()
            
            // Cache the updated rates
            saveRatesToCache()
            
            // Successfully updated fiat exchange rates
            return true
        } catch {
            // Error updating fiat exchange rates
            return false
        }
    }
    
    /// Convert an amount from USD to another fiat currency
    /// - Parameters:
    ///   - amount: Amount in USD
    ///   - toFiat: Target fiat currency code (lowercase)
    /// - Returns: The amount converted to the target currency, or nil if conversion not possible
    func convert(amount: Double, fromUSD toFiat: String) -> Double? {
        // If target is already USD, no conversion needed
        if toFiat.lowercased() == "usd" {
            return amount
        }
        
        // Need both USD and target fiat rates to perform conversion
        guard let usdRate = exchangeRates["usd"],
              let targetRate = exchangeRates[toFiat.lowercased()],
              usdRate > 0 else {
            return nil
        }
        
        // Convert through USDC: USD -> USDC -> Target Fiat
        // If 1 USDC = X USD and 1 USDC = Y EUR, then 1 USD = Y/X EUR
        return amount * (targetRate / usdRate)
    }
}
