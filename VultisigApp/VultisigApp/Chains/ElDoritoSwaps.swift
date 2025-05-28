import Foundation
import WalletCore
import BigInt
import Tss

struct ElDoritoSwaps {
    let vaultHexPublicKey: String
    let vaultHexChainCode: String
    
    func getPreSignedImageHash(payload: OneInchSwapPayload, keysignPayload: KeysignPayload, incrementNonce: Bool) throws -> [String] {
        let inputData = try getPreSignedInputData(
            quote: payload.quote,
            keysignPayload: keysignPayload,
            incrementNonce: incrementNonce
        )
        let hashes = TransactionCompiler.preImageHashes(coinType: payload.fromCoin.coinType, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.dataHash.hexString]
    }
    
    func getSignedTransaction(payload: OneInchSwapPayload, keysignPayload: KeysignPayload, signatures: [String: TssKeysignResponse], incrementNonce: Bool) throws -> SignedTransactionResult {
        print("🔥 ElDoritoSwaps: Building signed transaction")
        print("🔥 ElDoritoSwaps: From token: \(payload.fromCoin.ticker), chain: \(payload.fromCoin.chain.rawValue)")
        print("🔥 ElDoritoSwaps: To token: \(payload.toCoin.ticker), chain: \(payload.toCoin.chain.rawValue)")
        print("🔥 ElDoritoSwaps: Amount: \(payload.quote.dstAmount)")
        
        let inputData = try getPreSignedInputData(
            quote: payload.quote,
            keysignPayload: keysignPayload,
            incrementNonce: incrementNonce
        )
        print("🔥 ElDoritoSwaps: Pre-signed input data created successfully")
        
        let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
        let transaction = try helper.getSignedTransaction(
            vaultHexPubKey: vaultHexPublicKey,
            vaultHexChainCode: vaultHexChainCode,
            inputData: inputData,
            signatures: signatures
        )
        print("🔥 ElDoritoSwaps: Transaction signed successfully: \(transaction.transactionHash)")
        return transaction
    }
    
    func getPreSignedInputData(quote: OneInchQuote, keysignPayload: KeysignPayload, incrementNonce: Bool) throws -> Data {
        print("🔥 ElDoritoSwaps: Creating pre-signed input data")
        print("🔥 ElDoritoSwaps: To address: \(quote.tx.to)")
        print("🔥 ElDoritoSwaps: Value: \(quote.tx.value)")
        print("🔥 ElDoritoSwaps: Data first 100 chars: \(quote.tx.data.prefix(100))...")
        
        let input = EthereumSigningInput.with {
            $0.toAddress = quote.tx.to
            $0.transaction = .with {
                $0.contractGeneric = .with {
                    $0.amount = (BigUInt(quote.tx.value) ?? BigUInt.zero).serialize()
                    $0.data = Data(hex: quote.tx.data.stripHexPrefix())
                    print("🔥 ElDoritoSwaps: Data length: \($0.data.count) bytes")
                }
            }
        }
        
        let gasPrice = BigUInt(quote.tx.gasPrice) ?? BigUInt.zero
        // sometimes the `gas` field in oneinch tx is 0
        // when it is 0, we need to override it with defaultETHSwapGasUnit(600000)
        let normalizedGas = quote.tx.gas == 0 ? EVMHelper.defaultETHSwapGasUnit : quote.tx.gas
        let gas = BigUInt(normalizedGas)
        let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
        let signed = try helper.getPreSignedInputData(signingInput: input, keysignPayload: keysignPayload, gas: gas, gasPrice: gasPrice, incrementNonce: incrementNonce)
        return signed
    }
}

