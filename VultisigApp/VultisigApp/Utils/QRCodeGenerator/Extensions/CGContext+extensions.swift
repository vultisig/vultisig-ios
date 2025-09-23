import CoreGraphics
import Foundation

// MARK: - CGContext GState block

extension CGContext {
    /// Execute the supplied block within a `saveGState() / restoreGState()` pair, providing a context
    /// to draw in during the execution of the block
    ///
    /// - Parameter stateBlock: The block to execute within the new graphics state
    /// - Parameter context: The context to draw into within the block
    ///
    /// Example usage:
    /// ```
    ///    context.usingGState { (ctx) in
    ///       ctx.addPath(unsetBackground)
    ///       ctx.setFillColor(bgc1.cgColor)
    ///       ctx.fillPath(using: .evenOdd)
    ///    }
    /// ```
    @inlinable func usingGState(stateBlock: (_ context: CGContext) throws -> Void) rethrows {
        self.saveGState()
        defer {
            self.restoreGState()
        }
        try stateBlock(self)
    }
}
