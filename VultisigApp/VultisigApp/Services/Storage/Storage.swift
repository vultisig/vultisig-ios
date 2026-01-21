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
    
    @MainActor func save() throws {
        try modelContext.save()
    }

    @MainActor func insert<T>(_ model: T) where T: PersistentModel {
        modelContext.insert(model)
    }
    
    @MainActor func insert<T>(_ models: [T]) where T: PersistentModel {
        for model in models {
            modelContext.insert(model)
        }
    }

    @MainActor func delete<T>(_ model: T) where T: PersistentModel {
        modelContext.delete(model)
    }
}
