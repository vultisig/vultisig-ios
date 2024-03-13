import Foundation
import SwiftUI

@MainActor
public class LitecoinUnspentOutputsService: ObservableObject {
	@Published var walletData: LitecoinTransaction?
	@Published var errorMessage: String?
	
	func fetchLitecoinUnspentOutputs(for address: String) async {
		guard let url = URL(string: "https://litecoinspace.org/api/address/\(address)/utxo") else {
			self.errorMessage = "Invalid URL"
			return
		}
		
		do {
			let (data, _) = try await URLSession.shared.data(from: url)
			let decoder = JSONDecoder()
			let decodedData = try decoder.decode(LitecoinTransaction.self, from: data)
			
			self.walletData = decodedData // Update to reflect the new data type
		} catch {
			self.errorMessage = "Fetch failed: \(error.localizedDescription)"
		}
	}
}
