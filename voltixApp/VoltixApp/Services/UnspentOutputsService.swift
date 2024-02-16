//
//  UnspentOutputsViewModel.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 13/02/2024.
//

import Foundation
import SwiftUI

@MainActor  // Ensures all updates are on the main thread
public class UnspentOutputsService: ObservableObject {
    @Published var walletData: WalletUnspentOutput?
    @Published var errorMessage: String?
    
    // Replace with your actual function to fetch unspent outputs
    func fetchUnspentOutputs(for address: String) async {
        guard
            let url = URL(
                string: "https://api.blockcypher.com/v1/btc/main/addrs/\(address)?unspentOnly=true")
        else {
            // Handle the case for an invalid URL
            print("Invalid URL")
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Decode the JSON data into WalletUnspentOutput
            let decoder = JSONDecoder()
            let decodedData = try decoder.decode(WalletUnspentOutput.self, from: data)
            // Update your published property with the decoded data
            self.walletData = decodedData            
        } catch {
            // Handle any errors
            print("Fetch failed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
        }
    }
}

// https://api.blockcypher.com/v1/btc/main/addrs/18cBEMRxXHqzWWCxZNtU91F5sbUNKhL5PX?unspentOnly=true
