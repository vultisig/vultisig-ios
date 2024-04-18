//
//  BaseService.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 18/04/2024.
//

import Foundation
import BigInt

class BaseService: RpcEvmService {
    static let rpcEndpoint = Endpoint.baseServiceRpcService
    static let shared = BaseService(rpcEndpoint)
}
