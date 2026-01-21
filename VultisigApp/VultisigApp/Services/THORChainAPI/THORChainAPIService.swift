//
//  THORChainAPIService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

import Foundation

struct THORChainAPIService {
    let httpClient: HTTPClientProtocol
    private let decoder = JSONDecoder()
    let cache = THORChainAPICache()

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

    func getAddressLookup(address: String) async throws -> String {
        do {
            let response = try await httpClient.request(THORChainAPI.getAddressLookup(thorname: address), responseType: [String].self)
            guard let thorname = response.data.first else {
                throw THORChainAPIError.addressNotFound
            }

            return thorname
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
        // Check cache first
        if let cached = await cache.getCachedPools() {
            return cached
        }

        // Fetch from network
        let response = try await httpClient.request(THORChainAPI.getPools, responseType: [THORChainPoolResponse].self)
        let data = response.data

        // Cache the result
        await cache.cachePools(data)

        return data
    }

    func getPoolAsset(asset: String) async throws -> THORChainPoolResponse {
        let response = try await httpClient.request(THORChainAPI.getPoolAsset(asset: asset), responseType: THORChainPoolResponse.self)
        return response.data
    }

    func getNetwork() async throws -> ThorchainNetwork {
        let response = try await httpClient.request(THORChainAPI.getNetworkFees, responseType: ThorchainNetwork.self)
        return response.data
    }

    func getNetworkInfo() async throws -> THORChainNetworkInfo {
        // Check cache first
        if let cached = await cache.getCachedNetworkInfo() {
            return cached
        }

        // Fetch from network
        let response = try await httpClient.request(THORChainAPI.getNetworkInfo, responseType: THORChainNetworkInfo.self)
        let data = response.data

        // Cache the result
        await cache.cacheNetworkInfo(data)

        return data
    }

    func getHealth() async throws -> THORChainHealth {
        // Check cache first
        if let cached = await cache.getCachedHealth() {
            return cached
        }

        // Fetch from network
        let response = try await httpClient.request(THORChainAPI.getHealth, responseType: THORChainHealth.self)
        let data = response.data

        // Cache the result
        await cache.cacheHealth(data)

        return data
    }

    func getConstants() async throws -> ThorchainConstantsResponse {
        let response = try await httpClient.request(THORChainAPI.getConstants, responseType: ThorchainConstantsResponse.self)
        return response.data
    }
}
