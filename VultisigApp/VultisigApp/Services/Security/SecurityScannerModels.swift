//
//  SecurityScannerModels.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

import BigInt

struct SecurityScannerTransaction {
    let chain: Chain
    let type: SecurityTransactionType
    let from: String
    let to: String
    let amount: BigInt
    let data: String

    init(
        chain: Chain,
        type: SecurityTransactionType,
        from: String,
        to: String,
        amount: BigInt = BigInt.zero,
        data: String = "0x"
    ) {
        self.chain = chain
        self.type = type
        self.from = from
        self.to = to
        self.amount = amount
        self.data = data
    }
}

struct SecurityScannerMetadata: Equatable {
    let requestId: String
    let classification: String
    let resultType: String

    init(
        requestId: String = "",
        classification: String = "",
        resultType: String = ""
    ) {
        self.requestId = requestId
        self.classification = classification
        self.resultType = resultType
    }
}

enum SecurityTransactionType: String {
    case coinTransfer = "COIN_TRANSFER"
    case tokenTransfer = "TOKEN_TRANSFER"
    case swap = "SWAP"
    case approval = "APPROVAL"
    case smartContract = "SMART_CONTRACT"
}

struct SecurityScannerResult: Equatable {
    let provider: String
    let isSecure: Bool
    let riskLevel: SecurityRiskLevel
    let warnings: [SecurityWarning]
    let description: String?
    let recommendations: String
    let metadata: SecurityScannerMetadata
}

struct SecurityWarning: Equatable {
    let type: SecurityRiskLevel
    let severity: String
    let message: String
    let details: String?
}

enum SecurityRiskLevel: String, Equatable {
    case none = "NONE"
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
    case critical = "CRITICAL"
}

enum SecurityScannerFeaturesType {
    case scanTransaction
}

struct SecurityScannerSupport {
    let provider: String
    let feature: [Feature]

    struct Feature {
        let chains: [Chain]
        let featureType: SecurityScannerFeaturesType
    }
}
