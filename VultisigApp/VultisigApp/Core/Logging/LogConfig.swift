//
//  LogConfig.swift
//  VultisigApp
//
//  Runtime gate for the `Log` facade. Parses a `VULTI_LOG` selector string into
//  rules and resolves, per (feature, layer), the minimum enabled level — or `.off`
//  when the category is disabled. Pure and injectable so the gate is unit-testable
//  without an OSLog backend.
//
//  Grammar (comma-separated `selector:level`):
//    selector = "*" | "<feature>" | ".<layer>" | "<feature>.<layer>"
//    level    = debug | info | notice | warning | error | off
//  Resolution is MOST-SPECIFIC-WINS: exact (feature.layer) > feature > layer >
//  wildcard; ties are broken by the last-declared rule. `off` disables the category.
//
//  Example: "swap:debug,.network:off,*:info"
//    → swap.*   = debug (feature beats wildcard)
//    → *.network = off  (layer beats wildcard)
//    → all else = info  (wildcard)
//

import Foundation

/// A logging level, ordered from most verbose (`debug`) to `off` (disabled).
enum LogLevel: Int, Sendable, Comparable, CaseIterable {
    case debug = 0
    case info
    case notice
    case warning
    case error
    /// Sentinel above every real level: a category whose minimum level is `.off` emits nothing.
    case off

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Parses a level token (case-insensitive). Returns `nil` for unknown tokens.
    init?(token: String) {
        switch token.trimmingCharacters(in: .whitespaces).lowercased() {
        case "debug": self = .debug
        case "info": self = .info
        case "notice": self = .notice
        case "warning", "warn": self = .warning
        case "error": self = .error
        case "off", "none", "disabled": self = .off
        default: return nil
        }
    }
}

/// An immutable snapshot of the logging gate. `Sendable` value type, swapped
/// atomically by `LogGate` (and directly in tests).
struct LogConfig: Sendable {

    /// One parsed `selector:level` rule.
    struct Rule: Sendable {
        let feature: LogFeature?   // nil ⇒ matches any feature
        let layer: LogLayer?       // nil ⇒ matches any layer
        let level: LogLevel
        let order: Int             // declaration index, used to break specificity ties

        /// exact (feature.layer)=3 > feature=2 > layer=1 > wildcard=0.
        var specificity: Int { (feature == nil ? 0 : 2) + (layer == nil ? 0 : 1) }

        func matches(_ f: LogFeature, _ l: LogLayer) -> Bool {
            (feature == nil || feature == f) && (layer == nil || layer == l)
        }
    }

    private let rules: [Rule]
    /// Applied when no rule matches (only reachable when the string has no `*` rule).
    private let fallback: LogLevel

    init(rules: [Rule], fallback: LogLevel = .info) {
        self.rules = rules
        self.fallback = fallback
    }

    /// Builds a config from a `VULTI_LOG` selector string. Unknown selectors/levels are skipped.
    init(parsing raw: String, fallback: LogLevel = .info) {
        var parsed: [Rule] = []
        var index = 0
        for rawEntry in raw.split(separator: ",") {
            let entry = rawEntry.trimmingCharacters(in: .whitespaces)
            guard !entry.isEmpty else { continue }
            let parts = entry.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let level = LogLevel(token: String(parts[1])) else { continue }
            let selector = parts[0].trimmingCharacters(in: .whitespaces)
            guard let (feature, layer) = Self.parseSelector(selector) else { continue }
            parsed.append(Rule(feature: feature, layer: layer, level: level, order: index))
            index += 1
        }
        self.init(rules: parsed, fallback: fallback)
    }

    /// Parses one selector into (feature?, layer?), matching the documented grammar
    /// exactly: `*` | `<feature>` | `.<layer>` | `<feature>.<layer>`. Returns `nil`
    /// for anything malformed (`feature.`, `.`, bare layer names, unknown tokens).
    private static func parseSelector(_ selector: String) -> (LogFeature?, LogLayer?)? {
        if selector == "*" { return (nil, nil) }
        if selector.contains(".") {
            let segs = selector.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            let featurePart = segs[0].trimmingCharacters(in: .whitespaces)
            let layerPart = segs.count > 1 ? segs[1].trimmingCharacters(in: .whitespaces) : ""
            // A dotted selector must carry a real layer segment; reject `feature.` and `.`.
            guard !layerPart.isEmpty, let layer = LogLayer(rawValue: layerPart) else { return nil }
            if featurePart.isEmpty { return (nil, layer) }                 // ".layer"
            guard let feature = LogFeature(rawValue: featurePart) else { return nil }
            return (feature, layer)                                        // "feature.layer"
        }
        // Bare word is a feature; layers must use the leading-dot `.layer` form.
        guard let feature = LogFeature(rawValue: selector) else { return nil }
        return (feature, nil)
    }

    /// The minimum enabled level for a (feature, layer). `.off` ⇒ the category is disabled.
    func minLevel(_ feature: LogFeature, _ layer: LogLayer) -> LogLevel {
        var best: Rule?
        for rule in rules where rule.matches(feature, layer) {
            guard let current = best else { best = rule; continue }
            if rule.specificity > current.specificity
                || (rule.specificity == current.specificity && rule.order > current.order) {
                best = rule
            }
        }
        return best?.level ?? fallback
    }

    /// Whether the (feature, layer) category emits at all.
    func isEnabled(_ feature: LogFeature, _ layer: LogLayer) -> Bool {
        minLevel(feature, layer) != .off
    }

    /// Whether a specific level clears the category's minimum-level floor.
    ///
    /// The A1 facade enforces category on/off by handing out a live vs disabled
    /// `os.Logger`; it does not per-level filter a live logger (that would require
    /// wrapping the message). This predicate is the seam for opt-in level-aware call
    /// paths (and a future debug toggle screen) that want the `VULTI_LOG` minimum
    /// level honoured without losing native OSLog interpolation.
    func isEnabled(_ feature: LogFeature, _ layer: LogLayer, _ level: LogLevel) -> Bool {
        let floor = minLevel(feature, layer)
        return floor != .off && level >= floor
    }
}
