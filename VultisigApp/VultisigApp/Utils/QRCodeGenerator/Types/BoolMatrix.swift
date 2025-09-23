//
//  BoolMatrix.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import Foundation

class BoolMatrix {
    private var content: Matrix<Bool>

    convenience init() {
        self.init(dimension: 0, flattened: [])
    }

    init(dimension: Int, flattened: [Bool]) {
        self.content = Matrix(
            rows: dimension,
            columns: dimension,
            flattened: flattened)
    }

    var dimension: Int {
        return content.rows
    }

    subscript(row: Int, column: Int) -> Bool {
        get {
            return content[row, column]
        }
        set {
            content[row, column] = newValue
        }
    }
}
