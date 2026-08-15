//
//  ObservedTransient.swift
//  VultisigApp
//
//  Observation-tracked storage for per-session state that hangs off a SwiftData
//  `@Model` but is deliberately kept out of the schema.
//

import Foundation
import Observation

/// A box holding one value that publishes through the Observation registrar.
///
/// SwiftData excludes `@Transient` properties from a `@Model`'s observation
/// graph. Writing one publishes nothing — not even when the value genuinely
/// changes — so a SwiftUI view reading anything derived from it is never
/// re-evaluated. That was measured directly: a deferred write of a *changing*
/// value to a `@Transient` property produced the same single body evaluation as
/// a control that wrote nothing at all. Views built on such a property appeared
/// to work only because an unrelated `Storage.shared.save()` re-rendered the
/// tree soon afterwards, which is an accident of neighbouring code rather than a
/// mechanism.
///
/// Holding the value on a plain `@Observable` object restores publication. The
/// model keeps a `@Transient` reference to the box; that reference is assigned
/// once and never reassigned, so the fact that reading it is untracked costs
/// nothing, while the read of ``value`` inside a view body registers with the
/// registrar exactly as a persisted property would. The state stays session
/// scoped and stays out of the schema, so no migration is involved.
///
/// The setter is equality-guarded. Observation's generated setters notify
/// without comparing new to old, and a redundant notification from a deferred
/// writer is the shape that drives a runaway re-render, so the comparison lives
/// here instead of being re-derived at every call site.
@Observable
final class ObservedTransient<Value: Equatable> {
    private var storage: Value

    var value: Value {
        get { storage }
        set {
            guard newValue != storage else { return }
            storage = newValue
        }
    }

    init(_ value: Value) {
        self.storage = value
    }
}
