//
//  THORChainAPI.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

import Foundation

enum THORChainAPI: TargetType {
    case thornameDetails(name: String)
    case lastBlock
    
    var baseURL: URL {
        URL(string: "https://thornode.ninerealms.com/thorchain")!
    }
    
    var path: String {
        switch self {
        case .thornameDetails(let name):
            return "/thorname/\(name)"
        case .lastBlock:
            return "/lastblock"
        }
    }
    
    var method: HTTPMethod {
        switch self {
        case .thornameDetails, .lastBlock:
            return .get
        }
    }
    
    var task: HTTPTask {
        switch self {
        case .thornameDetails, .lastBlock:
            return .requestPlain
        }
    }
    
    
}
