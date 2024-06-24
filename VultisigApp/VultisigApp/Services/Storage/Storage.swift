//
//  Storage.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 22.05.2024.
//

import Foundation
import SwiftData

final class Storage {
    
    static let shared = Storage()
    
    var modelContext: ModelContext!
    
    @MainActor func save<T>(_ model: T) async throws where T : PersistentModel {
        try modelContext.save()
    }

    @MainActor func save<T>(_ models: [T]) async throws where T : PersistentModel {
        try modelContext.save()
    }

    @MainActor func insert<T>(_ models: [T]) async where T : PersistentModel {
        for model in models {
            modelContext.insert(model)
        }
    }

    @MainActor func delete<T>(_ model: T) async where T : PersistentModel {
        modelContext.delete(model)
    }
}
