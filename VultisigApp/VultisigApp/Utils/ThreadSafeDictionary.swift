//
//  ThreadSafeDictionary.swift
//  VultisigApp
//
//  Created by Johnny Luo on 18/4/2024.
//

import Foundation

class ThreadSafeDictionary<Key: Hashable, Value> {
    private var dictionary: [Key: Value] = Dictionary(minimumCapacity: 1000)
    private let queue = DispatchQueue(label: "ThreadSafeDictionaryQueue", attributes: .concurrent)
    
    func get(_ key: Key) -> Value? {
        return queue.sync {
            return dictionary[key]
        }
    }
    
    func set(_ key: Key, _ value: Value) {
        queue.async(flags: .barrier) {
            self.dictionary[key] = value
        }
    }
}
