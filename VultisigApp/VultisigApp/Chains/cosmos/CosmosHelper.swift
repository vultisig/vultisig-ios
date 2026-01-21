//
//  CosmosHelper.swift
//  VultisigApp
//
//  Refactored to use enum (value type) instead of classes
//

import Foundation
import WalletCore
import Tss
import VultisigCommonData

enum CosmosHelper {
    case gaiaChain
    case dydx
    case kujira
    case osmosis
    case terra
    case terraClassic
    case noble
    case akash

    // MARK: - Factory Methods

    static func getHelper(forChain chain: Chain) throws -> CosmosHelper {
        switch chain {
        case .gaiaChain:
            return .gaiaChain
        case .dydx:
            return .dydx
        case .kujira:
            return .kujira
        case .osmosis:
            return .osmosis
        case .terra:
            return .terra
        case .terraClassic:
            return .terraClassic
        case .noble:
            return .noble
        case .akash:
            return .akash
        default:
            throw HelperError.runtimeError("Unsupported Cosmos chain: \(chain)")
        }
    }

    // MARK: - Service Implementation

    private func makeHelperStruct() throws -> CosmosHelperStruct {
        let config = try CosmosHelperConfig.getConfig(forChain: chain)
        return CosmosHelperStruct(config: config)
    }

    private var chain: Chain {
        switch self {
        case .gaiaChain:
            return .gaiaChain
        case .dydx:
            return .dydx
        case .kujira:
            return .kujira
        case .osmosis:
            return .osmosis
        case .terra:
            return .terra
        case .terraClassic:
            return .terraClassic
        case .noble:
            return .noble
        case .akash:
            return .akash
        }
    }

    // MARK: - Public API

    func getSwapPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        let helper = try makeHelperStruct()
        return try helper.getSwapPreSignedInputData(keysignPayload: keysignPayload)
    }

    func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        // Handle special cases for Terra and Dydx
        switch self {
        case .terra, .terraClassic:
            return try TerraHelperStruct.getPreSignedInputData(keysignPayload: keysignPayload, chain: chain)
        case .dydx:
            return try DydxHelperStruct.getPreSignedInputData(keysignPayload: keysignPayload)
        default:
            let helper = try makeHelperStruct()
            return try helper.getPreSignedInputData(keysignPayload: keysignPayload)
        }
    }

    func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        switch self {
        case .terra, .terraClassic:
            return try TerraHelperStruct.getPreSignedImageHash(keysignPayload: keysignPayload, chain: chain)
        case .dydx:
            return try DydxHelperStruct.getPreSignedImageHash(keysignPayload: keysignPayload)
        default:
            let helper = try makeHelperStruct()
            return try helper.getPreSignedImageHash(keysignPayload: keysignPayload)
        }
    }

    func getSignedTransaction(keysignPayload: KeysignPayload,
                              signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        switch self {
        case .terra, .terraClassic:
            return try TerraHelperStruct.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures, chain: chain)
        case .dydx:
            return try DydxHelperStruct.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures)
        default:
            let helper = try makeHelperStruct()
            return try helper.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures)
        }
    }

    func getSignedTransaction(coinHexPublicKey: String,
                              inputData: Data,
                              signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        switch self {
        case .terra, .terraClassic:
            return try TerraHelperStruct.getSignedTransaction(coinHexPublicKey: coinHexPublicKey, inputData: inputData, signatures: signatures, chain: chain)
        case .dydx:
            return try DydxHelperStruct.getSignedTransaction(coinHexPublicKey: coinHexPublicKey, inputData: inputData, signatures: signatures)
        default:
            let helper = try makeHelperStruct()
            return try helper.getSignedTransaction(coinHexPublicKey: coinHexPublicKey, inputData: inputData, signatures: signatures)
        }
    }
}
