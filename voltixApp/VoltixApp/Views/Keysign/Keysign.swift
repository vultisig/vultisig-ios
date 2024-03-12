	//
	//  Keysign.swift
	//  VoltixApp

import Dispatch
import Foundation
import Mediator
import OSLog
import SwiftUI
import Tss
import WalletCore

private let logger = Logger(subsystem: "keysign", category: "tss")
struct KeysignView: View {
	enum KeysignStatus {
		case CreatingInstance
		case KeysignECDSA
		case KeysignEdDSA
		case KeysignFinished
		case KeysignFailed
	}
	
	@Binding var presentationStack: [CurrentScreen]
	let keysignCommittee: [String]
	let mediatorURL: String
	let sessionID: String
	let keysignType: KeyType
	let messsageToSign: [String]
	@State var localPartyKey: String
	let keysignPayload: KeysignPayload? // need to pass it along to the next view
	@EnvironmentObject var appState: ApplicationState
	@State private var currentStatus = KeysignStatus.CreatingInstance
	@State private var keysignInProgress = false
	@State private var tssService: TssServiceImpl? = nil
	@State private var tssMessenger: TssMessengerImpl? = nil
	@State private var stateAccess: LocalStateAccessorImpl? = nil
	@State private var keysignError: String? = nil
	@State private var signature: String = ""
	@State var cache = NSCache<NSString, AnyObject>()
	@State var signatures = [String: TssKeysignResponse]()
	@State private var messagePuller = MessagePuller()
	
	@State private var txid: String = ""
	
	@StateObject private var etherScanService = EtherScanService()
	
	var body: some View {
		VStack {
			Spacer()
			switch self.currentStatus {
				case .CreatingInstance:
					KeyGenStatusText(status: "CREATING TSS INSTANCE... ")
				case .KeysignECDSA:
					KeyGenStatusText(status: "SIGNING USING ECDSA KEY... ")
				case .KeysignEdDSA:
					KeyGenStatusText(status: "SIGNING USING EdDSA KEY... ")
				case .KeysignFinished:
					KeyGenStatusText(status: "KEYSIGN FINISHED...")
					
					VStack {
						if let transactionHash = etherScanService.transactionHash {
							Text("Transaction Hash: \(transactionHash)")
						} else if let errorMessage = etherScanService.errorMessage {
							Text("Error: \(errorMessage)")
								.foregroundColor(.red)
						}
						
						if !txid.isEmpty {
							Text("Transaction Hash: \(txid)")
						}
						
							//                        Text("SIGNATURE: \(self.signature)")
							//                            .font(Font.custom("Menlo", size: 15)
							//                                .weight(.bold))
							//                            .multilineTextAlignment(.center)
							//
						Button(action: {
							self.presentationStack = [.listVaultAssetView]
						}) {
							HStack {
								Text("DONE".uppercased())
									.font(.title30MenloBlack)
								Image(systemName: "chevron.right")
									.resizable()
									.frame(width: 10, height: 15)
							}
						}
						.buttonStyle(PlainButtonStyle())
						
					}.onAppear {
						self.messagePuller.stop()
						guard let vault = appState.currentVault else {
							return
						}
						
							// TODO: the following logic can be moved to keysignPayload.swift , or some viewmodel
							// get bitcoin transaction
						if let keysignPayload {
							if keysignPayload.swapPayload != nil {
								let swaps = THORChainSwaps(vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
								let result = swaps.getSignedTransaction(keysignPayload: keysignPayload, signatures: self.signatures)
								switch result {
									case .success(let tx):
										print(tx)
									case .failure(let err):
										print(err.localizedDescription)
								}
								return
							}
							switch keysignPayload.coin.chain.name.lowercased() {
								case Chain.Bitcoin.name.lowercased():
									let utxoHelper = UTXOChainsHelper(coin: .bitcoin, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
									let result = utxoHelper.getSignedTransaction(keysignPayload: keysignPayload, signatures: self.signatures)
									switch result {
										case .success(let tx):
											print(tx)
											Task {
												do {
													self.txid = try await BitcoinTransactionsService.broadcastTransaction(tx)
													print("Transaction Broadcasted Successfully, txid: \(self.txid)")
												} catch let error as BitcoinTransactionError {
													switch error {
														case .invalidURL:
															print("Invalid URL.")
														case .httpError(let statusCode):
															print("HTTP Error with status code: \(statusCode).")
														case .apiError(let message):
															print("API Error: \(message)")
														case .unexpectedResponse:
															print("Unexpected response from the server.")
														case .unknown(let unknownError):
															print("An unknown error occurred: \(unknownError.localizedDescription)")
													}
												} catch {
													print("An unexpected error occurred: \(error.localizedDescription)")
												}
											}
											
										case .failure(let err):
											switch err {
												case HelperError.runtimeError(let errDetail):
													logger.error("Failed to get signed transaction,error:\(errDetail)")
												default:
													logger.error("Failed to get signed transaction,error:\(err.localizedDescription)")
											}
									}
								case Chain.BitcoinCash.name.lowercased():
									let utxoHelper = UTXOChainsHelper(coin: .bitcoinCash, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
									let result = utxoHelper.getSignedTransaction(keysignPayload: keysignPayload, signatures: self.signatures)
									switch result {
										case .success(let tx):
											print(tx)
										case .failure(let err):
											switch err {
												case HelperError.runtimeError(let errDetail):
													logger.error("Failed to get signed transaction,error:\(errDetail)")
												default:
													logger.error("Failed to get signed transaction,error:\(err.localizedDescription)")
											}
									}
								case Chain.Litecoin.name.lowercased():
									let utxoHelper = UTXOChainsHelper(coin: .litecoin, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
									let result = utxoHelper.getSignedTransaction(keysignPayload: keysignPayload, signatures: self.signatures)
									switch result {
										case .success(let tx):
											print(tx)
										case .failure(let err):
											switch err {
												case HelperError.runtimeError(let errDetail):
													logger.error("Failed to get signed transaction,error:\(errDetail)")
												default:
													logger.error("Failed to get signed transaction,error:\(err.localizedDescription)")
											}
									}
								case Chain.Ethereum.name.lowercased():
										// ETH
									if keysignPayload.coin.contractAddress.isEmpty {
										
										
										
										let result = EthereumHelper.getSignedTransaction(vaultHexPubKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode, keysignPayload: keysignPayload, signatures: self.signatures)
										switch result {
											case .success(let tx):
												Task {
													await etherScanService.broadcastTransaction(hex: tx, apiKey: AppConfiguration.etherScanApiKey)
												}
												
											case .failure(let err):
												switch err {
													case HelperError.runtimeError(let errDetail):
														logger.error("Failed to get signed transaction,error:\(errDetail)")
													default:
														logger.error("Failed to get signed transaction,error:\(err.localizedDescription)")
												}
										}
										
									} else {
											//It should work for all ERC20
										let result = ERC20Helper.getSignedTransaction(vaultHexPubKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode, keysignPayload: keysignPayload, signatures: self.signatures)
										switch result {
											case .success(let tx):
												Task {
													await etherScanService.broadcastTransaction(hex: tx, apiKey: AppConfiguration.etherScanApiKey)
												}
											case .failure(let err):
												switch err {
													case HelperError.runtimeError(let errDetail):
														logger.error("Failed to get signed transaction,error:\(errDetail)")
													default:
														logger.error("Failed to get signed transaction,error:\(err.localizedDescription)")
												}
										}
									}
								case Chain.THORChain.name.lowercased():
									let result = THORChainHelper.getSignedTransaction(vaultHexPubKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode, keysignPayload: keysignPayload, signatures: self.signatures)
									switch result {
										case .success(let tx):
											ThorchainService.shared.broadcastTransaction(jsonString: tx) { result in
												DispatchQueue.main.async {
													switch result {
														case .success(let txHash):
															self.txid = txHash
															print("Transaction successful, hash: \(txHash)")
														case .failure(let error):
															print(error)
															print("Transaction failed, error: \(error.localizedDescription)")
													}
												}
											}
										case .failure(let err):
											switch err {
												case HelperError.runtimeError(let errDetail):
													logger.error("Failed to get signed transaction,error:\(errDetail)")
												default:
													logger.error("Failed to get signed transaction,error:\(err.localizedDescription)")
											}
									}
								case Chain.Solana.name.lowercased():
									let result = SolanaHelper.getSignedTransaction(vaultHexPubKey: vault.pubKeyEdDSA, vaultHexChainCode: vault.hexChainCode, keysignPayload: keysignPayload, signatures: self.signatures)
									switch result {
										case .success(let tx):
											print(tx)
											
											Task {
												await SolanaService.shared.sendSolanaTransaction(encodedTransaction: tx)
												
												await MainActor.run {
													self.txid = SolanaService.shared.transactionResult ?? ""
												}
											}
											
											
											
										case .failure(let err):
											switch err {
												case HelperError.runtimeError(let errDetail):
													logger.error("Failed to get signed transaction,error:\(errDetail)")
												default:
													logger.error("Failed to get signed transaction,error:\(err.localizedDescription)")
											}
									}
								default:
									logger.error("unsupported coin:\(keysignPayload.coin.ticker)")
							}
						}
					}.navigationBarBackButtonHidden(false)
				case .KeysignFailed:
					Text("Sorry keysign failed, you can retry it,error:\(self.keysignError ?? "")")
						.onAppear {
							self.messagePuller.stop()
						}
			}
			Spacer()
		}
		.task {
				// Create keygen instance, it takes time to generate the preparams
			guard let vault = appState.currentVault else {
				self.currentStatus = .KeysignFailed
				return
			}
			for msg in self.messsageToSign {
				let msgHash = Utils.getMessageBodyHash(msg: msg)
				self.tssMessenger = TssMessengerImpl(mediatorUrl: self.mediatorURL, sessionID: self.sessionID, messageID: msgHash)
				self.stateAccess = LocalStateAccessorImpl(vault: vault)
				var err: NSError?
					// keysign doesn't need to recreate preparams
				self.tssService = TssNewService(self.tssMessenger, self.stateAccess, false, &err)
				if let err {
					logger.error("Failed to create TSS instance, error: \(err.localizedDescription)")
					self.keysignError = err.localizedDescription
					self.currentStatus = .KeysignFailed
					return
				}
				guard let service = self.tssService else {
					logger.error("tss service instance is nil")
					self.currentStatus = .KeysignFailed
					return
				}
				self.messagePuller.pollMessages(mediatorURL: self.mediatorURL, sessionID: self.sessionID, localPartyKey: self.localPartyKey, tssService: service, messageID: msgHash)
				self.keysignInProgress = true
				let keysignReq = TssKeysignRequest()
				keysignReq.localPartyKey = vault.localPartyID
				keysignReq.keysignCommitteeKeys = self.keysignCommittee.joined(separator: ",")
				if let keysignPayload {
					switch keysignPayload.coin.chain.ticker {
						case "BTC":
							keysignReq.derivePath = CoinType.bitcoin.derivationPath()
						case "BCH":
							keysignReq.derivePath = CoinType.bitcoinCash.derivationPath()
						case "LTC":
							keysignReq.derivePath = CoinType.litecoin.derivationPath()
						case "ETH":
							keysignReq.derivePath = CoinType.ethereum.derivationPath()
						case "RUNE":
							keysignReq.derivePath = CoinType.thorchain.derivationPath()
						case "SOL":
							keysignReq.derivePath = CoinType.solana.derivationPath()
						default:
							logger.error("don't support this coin type")
							self.currentStatus = .KeysignFailed
					}
				}
					// sign messages one by one , since the msg is in hex format , so we need convert it to base64
					// and then pass it to TSS for keysign
				if let msgToSign = Data(hexString: msg)?.base64EncodedString() {
					keysignReq.messageToSign = msgToSign
				}
				
				do {
					switch self.keysignType {
						case .ECDSA:
							keysignReq.pubKey = vault.pubKeyECDSA
							self.currentStatus = .KeysignECDSA
						case .EdDSA:
							keysignReq.pubKey = vault.pubKeyEdDSA
							self.currentStatus = .KeysignEdDSA
					}
					if let service = self.tssService {
						let resp = try await tssKeysign(service: service, req: keysignReq, keysignType: keysignType)
						self.signatures[msg] = resp
							// TODO: save the signature with the message it signed
						self.signature = "R:\(resp.r), S:\(resp.s), RecoveryID:\(resp.recoveryID)"
					}
					self.messagePuller.stop()
				} catch {
					logger.error("fail to do keysign,error:\(error.localizedDescription)")
					self.keysignError = error.localizedDescription
					self.currentStatus = .KeysignFailed
					return
				}
			}
			
			self.currentStatus = .KeysignFinished
		}
	}
	
	private func tssKeysign(service: TssServiceImpl, req: TssKeysignRequest, keysignType: KeyType) async throws -> TssKeysignResponse {
		let t = Task.detached(priority: .high) {
			switch keysignType {
				case .ECDSA:
					return try service.keysignECDSA(req)
				case .EdDSA:
					return try service.keysignEdDSA(req)
			}
		}
		return try await t.value
	}
}

#Preview {
	KeysignView(presentationStack: .constant([]),
				keysignCommittee: [],
				mediatorURL: "",
				sessionID: "session",
				keysignType: .ECDSA,
				messsageToSign: ["message"],
				localPartyKey: "party id",
				keysignPayload: nil)
}
