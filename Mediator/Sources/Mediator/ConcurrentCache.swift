//
//  ActorCache.swift
//  Mediator
//
//  Created by Johnny Luo on 2/11/2025.
//

import Cache
import Foundation

class ConcurrentCache {
    let cache = MemoryStorage<String, Any>(config: MemoryConfig())
    private let queue = DispatchQueue(label: "com.vultisig.concurrentCache", attributes: .concurrent)

    func getAllKeys() -> [String] {
        return queue.sync { self.cache.allKeys }
    }

    func getObject(forKey key: String) throws -> Any? {
        var result: Any?
        var capturedError: Error?
        queue.sync {
            do {
                result = try self.cache.object(forKey: key)
            } catch {
                capturedError = error
            }
        }
        if let error = capturedError {
            throw error
        }
        return result
    }

    func objectExists(forKey key: String) -> Bool {
        return queue.sync { self.cache.objectExists(forKey: key) }
    }

    func setObject(_ obj: Any, forKey key: String) {
        queue.async(flags: .barrier) {
            if self.cache.objectExists(forKey: key) {
                self.cache.removeObject(forKey: key)
            }
            self.cache.setObject(obj, forKey: key)
        }
    }

    func removeObject(key: String) {
        queue.async(flags: .barrier) {
            self.cache.removeObject(forKey: key)
        }
    }

    func removeAll() {
        queue.async(flags: .barrier) {
            self.cache.removeAll()
        }
    }
}
