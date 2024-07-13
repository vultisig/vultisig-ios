//
//  CacheService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 12/07/24.
//

import Foundation

class CacheService {
    
    static let shared = CacheService()
    
    private let cache: URLCache
    private let cacheTimeout: TimeInterval
    
    private init(cache: URLCache = URLCache.shared, cacheTimeout: TimeInterval = 120) {
        self.cache = cache
        self.cacheTimeout = cacheTimeout
    }
    
    func getCachedData<T: Codable>(for key: String, type: T.Type) -> T? {
        guard let url = URL(string: key),
              let cachedResponse = cache.cachedResponse(for: URLRequest(url: url)),
              let cachedData = try? JSONDecoder().decode(CachedData<T>.self, from: cachedResponse.data),
              Date().timeIntervalSince(cachedData.timestamp) < cacheTimeout else {
            return nil
        }
        return cachedData.data
    }
    
    func setCachedData<T: Codable>(_ data: T, for key: String) throws {
        guard let url = URL(string: key) else { return }
        
        let cachedData = CachedData(data: data, timestamp: Date())
        let encodedData = try JSONEncoder().encode(cachedData)
        let cachedResponse = CachedURLResponse(response: URLResponse(), data: encodedData)
        cache.storeCachedResponse(cachedResponse, for: URLRequest(url: url))
    }
    
}
