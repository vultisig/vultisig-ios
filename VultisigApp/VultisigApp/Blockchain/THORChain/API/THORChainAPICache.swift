//
//  THORChainAPICache.swift
//  VultisigApp
//
//  Created by Claude Code on 21/10/2025.
//

import Foundation

/// Generic cache for API responses with configurable TTL
actor THORChainAPICache {

    /// Configurable cache duration in seconds (default: 5 minutes)
    static var cacheDuration: TimeInterval = 300 // 5 minutes

    private struct CacheEntry<T> {
        let value: T
        let timestamp: Date

        func isExpired(duration: TimeInterval) -> Bool {
            Date().timeIntervalSince(timestamp) > duration
        }
    }

    private var churnsCache: CacheEntry<[ChurnEntry]>?
    private var churnIntervalCache: CacheEntry<String>?
    private var networkInfoCache: CacheEntry<THORChainNetworkInfo>?
    private var healthCache: CacheEntry<THORChainHealth>?
    private var poolsCache: CacheEntry<[THORChainPoolResponse]>?
    private var poolStatsCache: CacheEntry<[THORChainPoolStats]>?

    // MARK: - Churns Cache

    func getCachedChurns() -> [ChurnEntry]? {
        guard let entry = churnsCache, !entry.isExpired(duration: Self.cacheDuration) else {
            return nil
        }
        return entry.value
    }

    func cacheChurns(_ churns: [ChurnEntry]) {
        churnsCache = CacheEntry(value: churns, timestamp: Date())
    }

    // MARK: - Churn Interval Cache

    func getCachedChurnInterval() -> String? {
        guard let entry = churnIntervalCache, !entry.isExpired(duration: Self.cacheDuration) else {
            return nil
        }
        return entry.value
    }

    func cacheChurnInterval(_ interval: String) {
        churnIntervalCache = CacheEntry(value: interval, timestamp: Date())
    }

    // MARK: - Network Info Cache

    func getCachedNetworkInfo() -> THORChainNetworkInfo? {
        guard let entry = networkInfoCache, !entry.isExpired(duration: Self.cacheDuration) else {
            return nil
        }
        return entry.value
    }

    func cacheNetworkInfo(_ info: THORChainNetworkInfo) {
        networkInfoCache = CacheEntry(value: info, timestamp: Date())
    }

    // MARK: - Health Cache

    func getCachedHealth() -> THORChainHealth? {
        guard let entry = healthCache, !entry.isExpired(duration: Self.cacheDuration) else {
            return nil
        }
        return entry.value
    }

    func cacheHealth(_ health: THORChainHealth) {
        healthCache = CacheEntry(value: health, timestamp: Date())
    }

    // MARK: - Pools Cache

    func getCachedPools() -> [THORChainPoolResponse]? {
        guard let entry = poolsCache, !entry.isExpired(duration: Self.cacheDuration) else {
            return nil
        }
        return entry.value
    }

    func cachePools(_ pools: [THORChainPoolResponse]) {
        poolsCache = CacheEntry(value: pools, timestamp: Date())
    }

    // MARK: - Pool Stats Cache

    func getCachedPoolStats() -> [THORChainPoolStats]? {
        guard let entry = poolStatsCache, !entry.isExpired(duration: Self.cacheDuration) else {
            return nil
        }
        return entry.value
    }

    func cachePoolStats(_ stats: [THORChainPoolStats]) {
        poolStatsCache = CacheEntry(value: stats, timestamp: Date())
    }

}
