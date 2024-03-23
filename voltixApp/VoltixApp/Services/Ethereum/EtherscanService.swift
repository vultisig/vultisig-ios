import SwiftUI
import Foundation
import BigInt

@MainActor
public class EtherScanService: ObservableObject {
	
	static let shared = EtherScanService()
	private init() {}
	
	var addressInfo: EthAddressInfo = EthAddressInfo()
	
	enum EtherScanError: Error {
		case invalidURL
		case httpError(Int, String)
		case apiError(String)
		case unexpectedResponse
		case decodingError(String)
		case unknown(Error)
		case resultParsingError
		case conversionError
		case jsonDecodingError
		case resultExtractionFailed
		case customError(String)
	}
	
		
	
	func getEthInfo(for address: String) async throws -> EthAddressInfo {
		
		let ethAddressInfo = EthAddressInfo()
		ethAddressInfo.address = address
		
		async let cryptoPrice = CryptoPriceService.shared.cryptoPrices?.prices[Chain.Ethereum.name.lowercased()]?["usd"]
		async let ethBalance = fetchEthRawBalance(address: address)
		async let tokens: [EthToken] = Utils.fetchArray(from: Endpoint.fetchEtherscanAddressTokensBalance(address: address))
		
		if let priceRateUsd = await cryptoPrice {
			ethAddressInfo.priceRate = priceRateUsd
		}
		
		ethAddressInfo.rawBalance = try await ethBalance
		
		ethAddressInfo.tokens = try await tokens
		
		self.addressInfo = ethAddressInfo
		return ethAddressInfo
	}
	
	func broadcastTransaction(hex: String) async throws -> String {
		let data = try await Utils.asyncPostRequest(urlString: Endpoint.broadcastEtherscanTransaction(hex: hex), headers: [:], body: Data())
		guard let result = extractResult(fromData: data) else {
			throw EtherScanError.resultExtractionFailed
		}
		return result
	}
	
	func fetchTransactions(forAddress address: String) async throws -> ([EtherscanAPITransactionDetail], String) {
		let decodedResponse: EtherscanAPIResponse = try await Utils.fetchObject(from: Endpoint.fetchEtherscanTransactions(address: address))
		if let transactions = decodedResponse.result {
			return (transactions, address)
		} else {
			throw EtherScanError.decodingError("Error to decode the transaction")
		}
	}
	
	func fetchERC20Transactions(forAddress address: String, contractAddress: String) async throws -> ([EtherscanAPITransactionDetail], String) {
		let decodedResponse:EtherscanAPIResponse = try await Utils.fetchObject(from: Endpoint.fetchERC20Transactions(address: address, contractAddress: contractAddress))
		if let transactions = decodedResponse.result {
			return (transactions, address)
		} else {
			throw EtherScanError.decodingError("Error to decode the transaction")
		}
	}
	
	func estimateGasForERC20Transfer(senderAddress: String, contractAddress: String, recipientAddress: String, value: BigInt) async throws -> BigInt {
		
		let data = constructERC20TransferData(recipientAddress: recipientAddress, value: value)
		let urlString = Endpoint.fetchEtherscanEstimateGasForERC20Transaction(data: data, contractAddress: contractAddress)
		let resultData = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
		
		guard let resultString = extractResult(fromData: resultData),
			  let resultHex = BigInt(resultString, radix: 16) else {
			throw EtherScanError.resultParsingError
		}
		
		return resultHex
	}
	
	func estimateGasForEthTransaction(senderAddress: String, recipientAddress: String, value: BigInt, memo: String?) async throws -> BigInt {
		let data = "0x" + (memo?.data(using: .utf8)?.map { String(format: "%02x", $0) }.joined() ?? "")
		let to = recipientAddress
		let valueHex = "0x" + String(value, radix: 16)
		let urlString = Endpoint.fetchEtherscanEstimateGasForEthTransaction(data: data, to: to, valueHex: valueHex)
		let resultData = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
		
		if let resultString = extractResult(fromData: resultData), let resultHex = BigInt(resultString, radix: 16) {
			return resultHex
		} else {
			throw EtherScanError.resultParsingError
		}
	}
	
	func fetchTokenBalance(contractAddress:String, address: String) async throws -> BigInt {
		let urlString = Endpoint.fetchEtherscanTokenBalance(contractAddress: contractAddress, address: address)
		let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
		if let resultString = extractResult(fromData: data),
		   let bigIntResult = BigInt(resultString, radix: 16) {
			return bigIntResult
		} else {
			throw EtherScanError.conversionError
		}
	}
	
	func fetchEthRawBalance(address: String) async throws -> String {
		let urlString = Endpoint.fetchEtherscanBalance(address: address)
		let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
		
		if let resultString = extractResult(fromData: data) {
			return resultString
		} else {
			throw EtherScanError.conversionError
		}
	}
	
		//TODO: cache it
	func fetchNonce(address: String) async throws -> Int64 {
		let urlString = Endpoint.fetchEtherscanTransactionCount(address: address)
		let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
		
		guard let resultString = extractResult(fromData: data) else {
			throw EtherScanError.jsonDecodingError
		}
		
		let trimmedResultString = resultString.trimmingCharacters(in: CharacterSet(charactersIn: "0x"))
		guard let intResult = Int64(trimmedResultString, radix: 16) else {
			throw EtherScanError.conversionError
		}
		
		return intResult
	}
	
		//TODO: cache it
	func fetchGasPrice() async throws -> BigInt {
		let urlString = Endpoint.fetchEtherscanGasPrice()
		let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
		if let resultString = extractResult(fromData: data) {
			let trimmedResultString = resultString.trimmingCharacters(in: CharacterSet(charactersIn: "0x"))
			if let bigIntResult = BigInt(trimmedResultString, radix: 16) {
				let bigIntResultGwei = bigIntResult / BigInt(1_000_000_000)
				return bigIntResultGwei
			} else {
				throw EtherScanError.conversionError
			}
		} else {
			throw EtherScanError.conversionError
		}
	}
	
	private func extractResult(fromData data: Data) -> String? {
		do {
			if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
			   let result = json["result"] as? String {
				return result
			}
		} catch {
			print("JSON decoding error: \(error)")
		}
		return nil
	}
	
	private func constructERC20TransferData(recipientAddress: String, value: BigInt) -> String {
		let methodId = "a9059cbb"
		let strippedRecipientAddress = recipientAddress.stripHexPrefix()
		let paddedAddress = strippedRecipientAddress.paddingLeft(toLength: 64, withPad: "0")
		let valueHex = String(value, radix: 16)
		let paddedValue = valueHex.paddingLeft(toLength: 64, withPad: "0")
		let data = "0x" + methodId + paddedAddress + paddedValue
		return data
	}
}
