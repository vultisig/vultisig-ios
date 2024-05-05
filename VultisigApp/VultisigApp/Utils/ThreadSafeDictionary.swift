//
//  ThreadSafeDictionary.swift
//  VultisigApp
//
//  Created by Johnny Luo on 18/4/2024.
//

import Foundation

class ThreadSafeDictionary<Key: Hashable, Value> {
    private var dictionary: [Key: Value] = [:]
    private let lock = NSLock()
    
    func get(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return dictionary[key]
    }
    
    func set(_ key: Key, _ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        dictionary[key] = value
    }
}
