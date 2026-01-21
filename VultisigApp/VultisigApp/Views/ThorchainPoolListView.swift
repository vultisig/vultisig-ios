import SwiftUI

struct ThorchainPoolListView: View {
    @State private var pools: [ThorchainPool] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding()
                } else if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                } else {
                    ForEach(pools, id: \.asset) { pool in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pool.asset)
                                .font(.headline)
                            
                            HStack {
                                Text("Status:")
                                Text(pool.status)
                                    .foregroundColor(pool.status == "Available" ? .green : .orange)
                            }
                            .font(.caption)
                            
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("RUNE Balance:")
                                    Text(formatBalance(pool.balanceRune))
                                        .font(.caption2)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing) {
                                    Text("Asset Balance:")
                                    Text(formatBalance(pool.balanceAsset))
                                        .font(.caption2)
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("THORChain Pools")
            .task {
                await loadPools()
            }
            .refreshable {
                await loadPools()
            }
        }
    }
    
    private func loadPools() async {
        isLoading = true
        errorMessage = nil
        
        do {
            pools = try await ThorchainService.shared.fetchLPPools()
            isLoading = false
        } catch {
            errorMessage = "Failed to load pools: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func formatBalance(_ balance: String) -> String {
        guard let value = Decimal(string: balance) else { return balance }
        let formatted = value / pow(10, 8) // Assuming 8 decimals
        return NumberFormatter.localizedString(from: NSDecimalNumber(decimal: formatted), number: .decimal)
    }
} 
