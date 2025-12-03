//
//  MayaChainAPIService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/11/2025.
//

import Foundation

struct MayaChainAPIService {
    let httpClient: HTTPClientProtocol
    private let decoder = JSONDecoder()
    let cache = MayaChainAPICache()

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func getNetwork() async throws -> MayaNetworkInfo {
        // Check cache first
        if let cached = await cache.getCachedNetworkInfo() {
            return cached
        }

        // Fetch from network
        let response = try await httpClient.request(MayaChainBondsAPI.getNetwork, responseType: MayaNetworkInfo.self)
        let data = response.data

        // Cache the result
        await cache.cacheNetworkInfo(data)

        return data
    }

    func getHealth(shouldCache: Bool = true) async throws -> MayaHealth {
        // Check cache first
        if shouldCache, let cached = await cache.getCachedHealth() {
            return cached
        }

        // Fetch from network
        let response = try await httpClient.request(MayaChainBondsAPI.getHealth, responseType: MayaHealth.self)
        let data = response.data

        // Cache the result
        await cache.cacheHealth(data)

        return data
    }

    func getPools() async throws -> [MayaPoolResponse] {
        // Check cache first
        if let cached = await cache.getCachedPools() {
            return cached
        }

        // Fetch from network
        let response = try await httpClient.request(MayaChainStakingAPI.getPools, responseType: [MayaPoolResponse].self)
        let data = response.data

        // Cache the result
        await cache.cachePools(data)

        return data
    }

    func getMimir() async throws -> MayaMimir {
        // Check cache first
        if let cached = await cache.getCachedMimir() {
            return cached
        }

        // Fetch from network
        let response = try await httpClient.request(MayaChainBondsAPI.getMimir, responseType: MayaMimir.self)
        let data = response.data

        // Cache the result
        await cache.cacheMimir(data)

        return data
    }
}

// MARK: - Cache

actor MayaChainAPICache {
    private var networkInfo: (data: MayaNetworkInfo, timestamp: Date)?
    private var health: (data: MayaHealth, timestamp: Date)?
    private var pools: (data: [MayaPoolResponse], timestamp: Date)?
    private var mimir: (data: MayaMimir, timestamp: Date)?

    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes

    func getCachedNetworkInfo() -> MayaNetworkInfo? {
        guard let cached = networkInfo,
              Date().timeIntervalSince(cached.timestamp) < cacheValidityDuration else {
            return nil
        }
        return cached.data
    }

    func cacheNetworkInfo(_ data: MayaNetworkInfo) {
        networkInfo = (data, Date())
    }

    func getCachedHealth() -> MayaHealth? {
        guard let cached = health,
              Date().timeIntervalSince(cached.timestamp) < cacheValidityDuration else {
            return nil
        }
        return cached.data
    }

    func cacheHealth(_ data: MayaHealth) {
        health = (data, Date())
    }

    func getCachedPools() -> [MayaPoolResponse]? {
        guard let cached = pools,
              Date().timeIntervalSince(cached.timestamp) < cacheValidityDuration else {
            return nil
        }
        return cached.data
    }

    func cachePools(_ data: [MayaPoolResponse]) {
        pools = (data, Date())
    }

    func getCachedMimir() -> MayaMimir? {
        guard let cached = mimir,
              Date().timeIntervalSince(cached.timestamp) < cacheValidityDuration else {
            return nil
        }
        return cached.data
    }

    func cacheMimir(_ data: MayaMimir) {
        mimir = (data, Date())
    }
}

// MARK: - Errors

enum MayaChainAPIError: Error, LocalizedError {
    case invalidResponse
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from MayaChain API"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
