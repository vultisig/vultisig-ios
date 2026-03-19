//
//  BlockaidAPI.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

import Foundation

enum BlockaidAPI {
    case scanBitcoinTransaction(BitcoinScanTransactionRequestJson)
    case scanEVMTransaction(EthereumScanTransactionRequestJson)
    case scanSolanaTransaction(SolanaScanTransactionRequestJson)
    case scanSuiTransaction(SuiScanTransactionRequestJson)
}

extension BlockaidAPI: TargetType {
    var baseURL: URL {
        return URL(string: "https://api.vultisig.com/blockaid/v0")!
    }

    var path: String {
        switch self {
        case .scanBitcoinTransaction:
            return "/bitcoin/transaction-raw/scan"
        case .scanEVMTransaction:
            return "/evm/transaction/scan"
        case .scanSolanaTransaction:
            return "/solana/message/scan"
        case .scanSuiTransaction:
            return "/sui/transaction/scan"
        }
    }

    var method: HTTPMethod {
        return .post
    }

    var task: HTTPTask {
        switch self {
        case .scanBitcoinTransaction(let request):
            return .requestCodable(request, .jsonEncoding)
        case .scanEVMTransaction(let request):
            return .requestCodable(request, .jsonEncoding)
        case .scanSolanaTransaction(let request):
            return .requestCodable(request, .jsonEncoding)
        case .scanSuiTransaction(let request):
            return .requestCodable(request, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        return [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
    }
}
