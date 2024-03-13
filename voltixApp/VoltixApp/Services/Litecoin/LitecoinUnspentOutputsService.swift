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
			let decodedData = try decoder.decode([LitecoinTransactionRef].self, from: data)
			let utxos = decodedData
			self.walletData = LitecoinTransaction(utxos: utxos)
		} catch let DecodingError.dataCorrupted(context) {
			self.errorMessage = "Data corrupted: \(context)"
		} catch let DecodingError.keyNotFound(key, context) {
			self.errorMessage = "Key '\(key)' not found: \(context.debugDescription)"
		} catch let DecodingError.valueNotFound(value, context) {
			self.errorMessage = "Value '\(value)' not found: \(context.debugDescription)"
		} catch let DecodingError.typeMismatch(type, context) {
			self.errorMessage = "Type '\(type)' mismatch: \(context.debugDescription)"
		} catch {
			self.errorMessage = "Error: \(error.localizedDescription)"
		}
		
		print(String(describing: self.errorMessage))
		
	}
}
