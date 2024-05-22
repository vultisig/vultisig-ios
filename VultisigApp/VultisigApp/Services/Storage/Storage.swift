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
        modelContext.insert(model)
        try modelContext.save()
    }
}
