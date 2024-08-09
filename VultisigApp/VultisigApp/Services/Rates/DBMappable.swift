//
//  DBMappable.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 08.08.2024.
//

import Foundation
import SwiftData
import CoreData

protocol DatabaseMappable {
    associatedtype Object: PersistentModel
    init(object: Object)
    func mapToObject() -> Object
}
