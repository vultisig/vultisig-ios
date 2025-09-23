import Foundation

class BoolMatrix {

    private var content: Array2D<Bool>

    convenience init() {
        self.init(dimension: 0, flattened: [])
    }

    init(dimension: Int, flattened: [Bool]) {
        self.content = Array2D(
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
