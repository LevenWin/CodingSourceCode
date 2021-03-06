//
//  MemoryStorage.swift
//  KingFisher
//
//  Created by leven on 2020/2/24.
//  Copyright © 2020 leven. All rights reserved.
//

import Foundation
/// Represents a set of conception related to storage which stores a certain type of value in memory.
/// This is a namespace for the memory storage types . A `Backend` with a certain `Config` will be used to describe the storage. See these composed types for more information.
public enum MemoryStorage {
    
    /// Represents a storage which stores a certain type of value in memory. It provides fast access, But limited storing size, The stored value type needs to conform to `CacheCostCalculabe`, and its `cacheCost` will be used to determine the cost of size for the cache item.
    
    /// You can config `MemoryStorage.Backend` in its initializer by passing a `MemoryStorage.Config` value.
    /// or modifying th `config` property after it being created. The backend of `MemoryStorage` has upper limitation on cost size in memory and item count. All item in the storage has an expiration date. When retrieved, if the target item is already expired, it will be recognized as it does not exist in the storage. The `MemoryStorage` also contains a schedule self clean task, to evict expired items from memory.
    public class Backend<T: CacheCostCalcuable> {
        let storage = NSCache<NSString, StorageObject<T>>()
        // Keys trackes the object once inside the storage. For object removing triggered by user, the corresponding key would be also removed. However, for the object removing triggered by cache rule/policy of system,the key will be remained there until next `removeExpired` happens.
        //
        // Breaking the strict tracking could save additional locking behaviors.
        var keys = Set<String>()
        
        private var cleanTimer: Timer? = nil
        private let lock = NSLock()
        
        // The config used in this storage. It is a value you can set and use to config the storage in air.
        public var config: Config {
            didSet {
                storage.totalCostLimit = config.totalCostLimit
                storage.countLimit = config.countLimit
            }
        }
        /// Creates a `MemoryStorage` with a given `config`.
        ///
        /// - Parameters config: The config used to create the storage. It determines the max size limitation. default expiration setting and more.
        
        public init(config: Config) {
            self.config = config
            
            cleanTimer = .scheduledTimer(withTimeInterval: config.cleanInterval, repeats: true, block: { [weak self](_) in
                guard let self = self else { return }
                self.removeExpired()
            })
        }
        
        func removeExpired() {
            lock.lock()
            defer {
                lock.unlock()
            }
            
            for key in keys {
                let nsKey = key as NSString
                guard let object = storage.object(forKey: nsKey) else {
                    // This could happen if the object is moved by cache `totalCostLimit` or `countLimit` rule.
                    // We didn't remove the key yet until now. since we do not want to introduce additonal lock.
                    keys.remove(key)
                    continue
                }
                
                if object.expired {
                    storage.removeObject(forKey: nsKey)
                    keys.remove(key)
                }
            }
        }
        // Storing in memory will not throw. It is just for meeting protocol requirement and forwarding to no throwing method
        func store(
            value: T,
            forKey key: String,
            expiration: StorageExpiration? = nil) throws
        {
            storeNoThrow(value: value, forKey: key, expiration: expiration)
        }
        
        // The no throw version for storing value in cache. Kingfisher knows the detail so it could use this version to make syntax simple internally
        func storeNoThrow(value: T, forKey key: String, expiration:  StorageExpiration? = nil)
        {
            lock.lock()
            defer { lock.unlock() }
            let expiration = expiration ?? config.expiration
            
            guard !expiration.isExpired else { return }
            
            let object = StorageObject(value, key: key, expiration: expiration)
            storage.setObject(object, forKey: key as NSString, cost: value.cacheCost)
            keys.insert(key)
        }
        /// Use this when you actually access the memory cached item.
        /// By default, this will extend the expired data for the accessed item
        /// - Parameters:
        ///     - key: Cache Key
        ///     - extendingExpiration: expiration to extend item expiration time:
        ///         * .none: The item expires after the original time,without extending after access.
        ///         * .cacheTime: The item expiration extends by the original cache time after each access.
        ///         * .expirationTime: The item expiration extends by the provided time after each access.
        /// - Returns: cached object or nil
        
        func value(forKey key: String, extendingExpiration: ExpirationExtending = .cacheTime) -> T? {
            guard let object = storage.object(forKey: key as NSString) else {
                return nil
            }
            if object.expired {
                return nil
            }
            object.extendExpiration(extendingExpiration)
            return object.value
        }
        
        func isCached(forKey key: String) -> Bool {
            guard let _ = value(forKey: key, extendingExpiration: .none) else {
                return false
            }
            return true
        }
        
        func remove(forKey key: String) throws {
            lock.lock()
            defer {
                lock.unlock()
            }
            storage.removeObject(forKey: key as NSString)
            keys.remove(key)
        }
        
        func removeAll() throws {
            lock.lock()
            defer { lock.unlock() }
            storage.removeAllObjects()
            keys.removeAll()
        }
    }
}

extension MemoryStorage {
    /// Represents the config used in a `MemoryStorage`.
    public struct Config {
        
        /// Total cost limit of the storage in bytes.
        public var totalCostLimit: Int
        /// The item count limit of the memory storage.
        public var countLimit: Int = .max
        /// The `StorageExpiration` used in  the memroy storage, Default is `.second(300)`.
        /// means that the memory cache would expire in 5 minutes.
        public var expiration: StorageExpiration = .seconds(300)
        /// The time Interval between the storage do clean work for swiping expired items
        public let cleanInterval: TimeInterval
        
        /// Creates a config from a given `totalCostLimit` value
        ///
        /// - Parameters:
        ///     - totalCostLimit: Total cost limit of the storage in bytes
        ///     - cleanInterval: The time interval between the storage do clean work for swiping expired items. Default is 120, means the auto eviction happens once per two minutes.
        /// - Note: Other member of `MemoryStorage.Config` will use theri default values when created
        public init(totalCostLimit: Int, cleanInterval: TimeInterval = 120) {
            self.totalCostLimit = totalCostLimit
            self.cleanInterval = cleanInterval
        }
    }
}

extension MemoryStorage {
    class StorageObject<T> {
        let value: T
        let expiration: StorageExpiration
        let key: String
        
        private(set) var estimatedExpiration: Date
        
        init(_ value: T, key: String, expiration: StorageExpiration) {
            self.value = value
            self.key = key
            self.expiration = expiration
            self.estimatedExpiration = expiration.estimatedExpirationSinceNow
        }
        
        func extendExpiration(_ extendingExpiration: ExpirationExtending = .cacheTime) {
            switch extendingExpiration {
            case .none:
                return
            case .cacheTime:
                self.estimatedExpiration = expiration.estimatedExpirationSinceNow
            case .expirationTime(let expirationTime):
                self.estimatedExpiration = expirationTime.estimatedExpirationSinceNow
            }
        }
        var expired: Bool {
            return estimatedExpiration.isPast
        }
    }
}
