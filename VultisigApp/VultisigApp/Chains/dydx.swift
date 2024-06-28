//
//  dydx.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 12/06/24.
//

import Foundation
import WalletCore
import Tss
import CryptoSwift

class DydxHelper {
    let coinType: CoinType
    
    init(){
        self.coinType = CoinType.dydx
    }
    
    static let DydxGasLimit:UInt64 = 2500000000000000
    
    func getSwapPreSignedInputData(keysignPayload: KeysignPayload,signingInput: CosmosSigningInput) -> Result<Data,Error> {
        guard case .Cosmos(let accountNumber, let sequence,let gas) = keysignPayload.chainSpecific else {
            return .failure(HelperError.runtimeError("fail to get account number and sequence"))
        }
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            return .failure(HelperError.runtimeError("invalid hex public key"))
        }
        var input = signingInput
        input.publicKey = pubKeyData
        input.accountNumber = accountNumber
        input.sequence = sequence
        input.mode = .sync
        
        input.fee = CosmosFee.with {
            $0.gas = 200000
            $0.amounts = [CosmosAmount.with {
                $0.denom = "adydx"
                $0.amount = String(gas)
            }]
        }
        // memo has been set
        // deposit message has been set
        do {
            let inputData = try input.serializedData()
            return .success(inputData)
        } catch {
            return .failure(HelperError.runtimeError("fail to get plan"))
        }
    }
    
    func getPreSignedInputData(keysignPayload: KeysignPayload) -> Result<Data, Error> {
        guard case .Cosmos(let accountNumber, let sequence , let gas) = keysignPayload.chainSpecific else {
            return .failure(HelperError.runtimeError("fail to get account number and sequence"))
        }
        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            return .failure(HelperError.runtimeError("invalid hex public key"))
        }
        let coin = self.coinType
        
        var message = [CosmosMessage()]
        
        var isDeposit: Bool = false
        var isVote: Bool = false
        if let memo = keysignPayload.memo, !memo.isEmpty {
            isDeposit = DepositStore.PREFIXES.contains(where: { memo.hasPrefix($0) })
            isVote = memo.hasPrefix("DYDX_VOTE")
        }
        
        if let swapPayload = keysignPayload.swapPayload {
            isDeposit = swapPayload.isDeposit
        }
        
        /*
         enum VoteOption {
         // VOTE_OPTION_UNSPECIFIED defines a no-op vote option.
         VOTE_OPTION_UNSPECIFIED = 0;
         // VOTE_OPTION_YES defines a yes vote option.
         VOTE_OPTION_YES = 1;
         // VOTE_OPTION_ABSTAIN defines an abstain vote option.
         VOTE_OPTION_ABSTAIN = 2;
         // VOTE_OPTION_NO defines a no vote option.
         VOTE_OPTION_NO = 3;
         // VOTE_OPTION_NO_WITH_VETO defines a no with veto vote option.
         VOTE_OPTION_NO_WITH_VETO = 4;
         }
         */
        
        if isDeposit, isVote {
            let selectedOption = keysignPayload.memo?.replacingOccurrences(of: "DYDX_VOTE:", with: "") ?? ""
            let components = selectedOption.split(separator: ":")
            
            guard components.count == 2,
                  let proposalID = Int(components[1]),
                  let voteOption = TW_Cosmos_Proto_Message.VoteOption.allCases.first(where: { $0.description == String(components[0]) }) else {
                return .failure(HelperError.runtimeError("The vote option is invalid"))
            }
            
            message = [CosmosMessage.with {
                $0.msgVote = CosmosMessage.MsgVote.with {
                    $0.proposalID = UInt64(proposalID)
                    $0.voter = keysignPayload.coin.address
                    $0.option = voteOption
                }
            }]
        } else {
            guard AnyAddress(string: keysignPayload.toAddress, coin: coin) != nil else {
                return .failure(HelperError.runtimeError("\(keysignPayload.toAddress) is invalid"))
            }
            
            message = [CosmosMessage.with {
                $0.sendCoinsMessage = CosmosMessage.Send.with{
                    $0.fromAddress = keysignPayload.coin.address
                    $0.amounts = [CosmosAmount.with {
                        $0.denom = "adydx"
                        $0.amount = String(keysignPayload.toAmount)
                    }]
                    $0.toAddress = keysignPayload.toAddress
                }
            }]
        }
        
        let input = CosmosSigningInput.with {
            $0.publicKey = pubKeyData
            $0.signingMode = .protobuf
            $0.chainID = coin.chainId
            $0.accountNumber = accountNumber
            $0.sequence = sequence
            $0.mode = .sync
            if let memo = keysignPayload.memo, !isVote {
                $0.memo = memo
            }
            $0.messages = message
            
            $0.fee = CosmosFee.with {
                $0.gas = 200000 // gas limit
                $0.amounts = [CosmosAmount.with {
                    $0.denom = "adydx"
                    $0.amount = String(gas)
                }]
            }
        }
        
        print(input.debugDescription)
        
        do {
            let inputData = try input.serializedData()
            return .success(inputData)
        } catch {
            return .failure(HelperError.runtimeError("fail to get plan"))
        }
    }
    
    func getPreSignedImageHash(keysignPayload: KeysignPayload) -> Result<[String], Error> {
        let result = getPreSignedInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            do {
                let hashes = TransactionCompiler.preImageHashes(coinType: self.coinType, txInputData: inputData)
                let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                
                print("ERROR preSigningOutput: \(preSigningOutput.errorMessage)")
                return .success([preSigningOutput.dataHash.hexString])
            } catch {
                return .failure(HelperError.runtimeError("fail to get preSignedImageHash,error:\(error.localizedDescription)"))
            }
        case .failure(let err):
            return .failure(err)
        }
    }
    
    func getSignedTransaction(vaultHexPubKey: String,
                              vaultHexChainCode: String,
                              keysignPayload: KeysignPayload,
                              signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult
    {
        let result = getPreSignedInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            return try getSignedTransaction(vaultHexPubKey: vaultHexPubKey, vaultHexChainCode: vaultHexChainCode, inputData: inputData, signatures: signatures)
            
        case .failure(let error):
            throw error
        }
    }
    
    func getSignedTransaction(vaultHexPubKey: String,
                              vaultHexChainCode: String,
                              inputData: Data,
                              signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult
    {
        let cosmosPublicKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: vaultHexPubKey, hexChainCode: vaultHexChainCode, derivePath: self.coinType.derivationPath())
        guard let pubkeyData = Data(hexString: cosmosPublicKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw HelperError.runtimeError("public key \(cosmosPublicKey) is invalid")
        }
        
        do {
            let hashes = TransactionCompiler.preImageHashes(coinType: self.coinType, txInputData: inputData)
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
            
            print(preSigningOutput.errorMessage)
            
            let allSignatures = DataVector()
            let publicKeys = DataVector()
            let signatureProvider = SignatureProvider(signatures: signatures)
            let signature = signatureProvider.getSignatureWithRecoveryID(preHash: preSigningOutput.dataHash)
            guard publicKey.verify(signature: signature, message: preSigningOutput.dataHash) else {
                throw HelperError.runtimeError("fail to verify signature")
            }
            
            allSignatures.add(data: signature)
            publicKeys.add(data: pubkeyData)
            let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: self.coinType,
                                                                                 txInputData: inputData,
                                                                                 signatures: allSignatures,
                                                                                 publicKeys: publicKeys)
            let output = try CosmosSigningOutput(serializedData: compileWithSignature)
            let serializedData = output.serialized
            let sig = try JSONDecoder().decode(CosmosSignature.self, from: serializedData.data(using: .utf8) ?? Data())
            let result = SignedTransactionResult(rawTransaction: serializedData, transactionHash:sig.getTransactionHash())
            return result
        } catch {
            throw HelperError.runtimeError("fail to get signed transaction,error:\(error.localizedDescription)")
        }
    }
}

