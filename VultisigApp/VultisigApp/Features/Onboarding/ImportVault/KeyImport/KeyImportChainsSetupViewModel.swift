//
//  KeyImportChainsSetupViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 02/12/2025.
//

import Foundation

enum KeyImportChainsState {
    case scanningChains
    case activeChains
    case customizeChains
}

final class KeyImportChainsSetupViewModel: ObservableObject {
    @Published var state: KeyImportChainsState = .scanningChains
    @Published var selectedChains = [Chain]()
    @Published var activeChains = [KeyImportChain]()
    @Published var otherChains = [KeyImportChain]()
    
    var selectedChainsCount: Int { selectedChains.count }
    var maxChainsExceeded: Bool { selectedChainsCount > maxChains }
    var buttonDisabled: Bool { selectedChains.isEmpty || maxChainsExceeded }
    var buttonTitle: String {
        maxChainsExceeded ? String(format: "youCanSelectXChains".localized, maxChains) : "continue".localized
    }
    var chainsToImport: [Chain] {
        selectedChains.isEmpty ? activeChains.map(\.chain) : selectedChains
    }
    
    let maxChains: Int = 4
    
    init() {}
    
    func onLoad() async {
        let activeChains = await fetchActiveChains()
        await MainActor.run {
            self.activeChains = activeChains
            self.otherChains = Chain.allCases
                .filter { !activeChains.map(\.chain).contains($0) }
                .map { KeyImportChain(chain: $0, balance: "$ 0.00") }
            self.state = .activeChains
        }
    }
    
    // TODO: - Add real implementation
    func fetchActiveChains() async -> [KeyImportChain] {
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        return [
            .init(chain: .thorChain, balance: "$ 2,000,000.00"),
            .init(chain: .bitcoin, balance: "$ 1,000,000.00"),
            .init(chain: .ethereum, balance: "$ 500,000.00"),
            .init(chain: .solana, balance: "$ 200,000.00"),
        ]
    }
    
    func isSelected(chain: KeyImportChain) -> Bool {
        selectedChains.contains(chain.chain)
    }
    
    func toggleSelection(chain: KeyImportChain, isSelected: Bool) {
        if isSelected {
            selectedChains.append(chain.chain)
        } else {
            selectedChains.removeAll { $0 == chain.chain }
        }
    }
}
