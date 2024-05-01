//
//  DeeplinkViewModel.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-05-01.
//

import SwiftUI

enum DeeplinkFlowType {
    case NewVault
    case SignTransaction
}

@MainActor
class DeeplinkViewModel: ObservableObject {
    @Published var type: DeeplinkFlowType? = nil
    @Published var selectedVault: Vault? = nil
    
    func extractParameters(_ url: URL) {
        print("App was opened via URL: \(url)")
        
        let queryItems = URLComponents(string: url.absoluteString)?.queryItems
        let jsonData = queryItems?.first(where: { $0.name == "jsonData" })?.value
        print(String(describing: jsonData))
    }
}
