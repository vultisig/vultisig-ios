//
//  THORChainAPIService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

import Foundation

struct THORChainAPIService {
    private let httpClient: HTTPClientProtocol
    private let decoder = JSONDecoder()
    
    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }
    
    func getThornameDetails(name: String) async throws -> THORName {
        do {
            let response = try await httpClient.request(THORChainAPI.getThornameDetails(name: name), responseType: THORName.self)
            return response.data
        } catch {
            switch error {
            case HTTPError.statusCode(500, let data):
                guard
                    let data,
                    let errorResponse = try? decoder.decode(THORChainErrorResponse.self, from: data),
                    errorResponse.message.contains("THORName doesn't exist")
                else { throw error }
                throw THORChainAPIError.thornameNotFound
            default:
                throw error
            }
        }
    }
    
    func getThornameLookup(name: String) async throws -> THORNameLookup {
        do {
            let response = try await httpClient.request(THORChainAPI.getThornameLookup(name: name), responseType: THORNameLookup.self)
            return response.data
        } catch {
            switch error {
            case HTTPError.statusCode(404, _):
                throw THORChainAPIError.thornameNotFound
            default:
                throw error
            }
        }
    }
    
    func getLastBlock() async throws -> UInt64 {
        let response = try await httpClient.request(THORChainAPI.getLastBlock, responseType: [LastBlockResponse].self)
        guard let blockheight = response.data.first?.thorchain else {
            throw THORChainAPIError.invalidResponse
        }
        return blockheight
    }
    
    func getPools() async throws -> [THORChainPoolResponse] {
        let response = try await httpClient.request(THORChainAPI.getPools, responseType: [THORChainPoolResponse].self)
        return response.data
    }
    
    func getPoolAsset(asset: String) async throws -> THORChainPoolResponse {
        let response = try await httpClient.request(THORChainAPI.getPoolAsset(asset: asset), responseType: THORChainPoolResponse.self)
        return response.data
    }
    
    func getNetworkInfo() async throws -> ThorchainNetworkAllFees {
        let response = try await httpClient.request(THORChainAPI.getNetworkInfo, responseType: ThorchainNetworkAllFees.self)
        return response.data
    }
}


