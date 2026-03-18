//
//  Matrix.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

struct Matrix<T> {
    let columns: Int
    let rows: Int
    private var array: [T]

    init(rows: Int, columns: Int, flattened: [T]) {
        precondition(rows * columns == flattened.count, "row/column counts don't match initial flattened data count")
        self.rows = rows
        self.columns = columns
        self.array = flattened
    }

    subscript(row: Int, column: Int) -> T {
        get {
            precondition(row < self.rows, "Row \(row) Index is out of range. Array2D<T>(rows:\(rows), columns: \(columns))")
            precondition(column < self.columns, "Column \(column) Index is out of range. Array2D<T>(rows:\(rows), columns: \(columns))")
            return self.array[(row * self.columns) + column]
        }
        set {
            precondition(row < self.rows, "Row \(row) Index is out of range. Array2D<T>(rows:\(rows), columns: \(columns))")
            precondition(column < self.columns, "Column \(column) Index is out of range. Array2D<T>(rows:\(rows), columns: \(columns))")
            self.array[(row * self.columns) + column] = newValue
        }
    }

    mutating func setIndexed(_ index: Int, value: T) {
        self.array[index] = value
    }
}
