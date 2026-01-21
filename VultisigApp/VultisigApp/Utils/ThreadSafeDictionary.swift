import Foundation

final class ThreadSafeDictionary<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
    private var dictionary: [Key: Value] = Dictionary(minimumCapacity: 1000)
    private let queue = DispatchQueue(label: "ThreadSafeDictionaryQueue", attributes: .concurrent)
    
    func get(_ key: Key) -> Value? {
        return queue.sync {
            return dictionary[key]
        }
    }
    func setSync(_ key: Key, _ value: Value) {
        queue.sync {
            self.dictionary[key] = value
        }
    }
    
    func set(_ key: Key, _ value: Value) {
        queue.async(flags: .barrier) {
            self.dictionary[key] = value
        }
    }
    
    func allItems() -> [Key: Value] {
        return queue.sync {
            return dictionary
        }
    }
    
    func allKeysInOrder() -> [Key] {
        return queue.sync {
            return Array(dictionary.keys)
        }
    }
    
    func clear() {
        queue.async(flags: .barrier) {
            self.dictionary.removeAll()
        }
    }
    func remove(_ key: Key) {
        queue.async(flags: .barrier) {
            self.dictionary.removeValue(forKey: key)
        }
    }
}
