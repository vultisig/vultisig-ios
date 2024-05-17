import Foundation

class ThreadSafeDictionary<Key: Hashable, Value> {
    private var dictionary: [Key: Value] = [:]
    private var orderedKeys: [Key] = []
    private let lock = NSLock()
    
    func get(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return dictionary[key]
    }
    
    func set(_ key: Key, _ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        if dictionary[key] == nil {
            orderedKeys.append(key)
        }
        dictionary[key] = value
    }
    
    func allItems() -> [Key: Value] {
        lock.lock()
        defer { lock.unlock() }
        return dictionary
    }
    
    func allKeysInOrder() -> [Key] {
        lock.lock()
        defer { lock.unlock() }
        return orderedKeys
    }
}
