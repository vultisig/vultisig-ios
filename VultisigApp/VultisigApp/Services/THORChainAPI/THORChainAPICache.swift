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
    private var poolStatsCache: CacheEntry<[THORChainPoolStats]>?
    private var depthHistoryCache: [String: CacheEntry<THORChainDepthHistory>] = [:] // Key: "asset-interval-count"
    private var manualAPRCache: [String: CacheEntry<Decimal>] = [:] // Key: "asset-days"

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

    func invalidateChurns() {
        churnsCache = nil
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

    func invalidateChurnInterval() {
        churnIntervalCache = nil
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

    func invalidateNetworkInfo() {
        networkInfoCache = nil
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

    func invalidateHealth() {
        healthCache = nil
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

    func invalidatePoolStats() {
        poolStatsCache = nil
    }

    // MARK: - Depth History Cache

    func getCachedDepthHistory(asset: String, interval: String, count: Int) -> THORChainDepthHistory? {
        let key = "\(asset)-\(interval)-\(count)"
        guard let entry = depthHistoryCache[key], !entry.isExpired(duration: Self.cacheDuration) else {
            return nil
        }
        return entry.value
    }

    func cacheDepthHistory(_ history: THORChainDepthHistory, asset: String, interval: String, count: Int) {
        let key = "\(asset)-\(interval)-\(count)"
        depthHistoryCache[key] = CacheEntry(value: history, timestamp: Date())
    }

    func invalidateDepthHistory(asset: String? = nil) {
        if let asset = asset {
            // Remove all entries for this asset
            depthHistoryCache = depthHistoryCache.filter { !$0.key.starts(with: "\(asset)-") }
        } else {
            // Clear all depth history cache
            depthHistoryCache.removeAll()
        }
    }

    // MARK: - Manual APR Cache

    func getCachedManualAPR(asset: String, days: Int) -> Decimal? {
        let key = "\(asset)-\(days)"
        guard let entry = manualAPRCache[key], !entry.isExpired(duration: Self.cacheDuration) else {
            return nil
        }
        return entry.value
    }

    func cacheManualAPR(_ apr: Decimal, asset: String, days: Int) {
        let key = "\(asset)-\(days)"
        manualAPRCache[key] = CacheEntry(value: apr, timestamp: Date())
    }

    func invalidateManualAPR(asset: String? = nil) {
        if let asset = asset {
            // Remove all entries for this asset
            manualAPRCache = manualAPRCache.filter { !$0.key.starts(with: "\(asset)-") }
        } else {
            // Clear all manual APR cache
            manualAPRCache.removeAll()
        }
    }

    // MARK: - Clear All Cache

    func clearAll() {
        churnsCache = nil
        churnIntervalCache = nil
        networkInfoCache = nil
        healthCache = nil
        poolStatsCache = nil
        depthHistoryCache.removeAll()
        manualAPRCache.removeAll()
    }
}
