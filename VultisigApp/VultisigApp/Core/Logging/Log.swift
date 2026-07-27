//
//  Log.swift
//  VultisigApp
//
//  The `Log` facade. `Log.<feature>.<layer>` hands back a *configured* `os.Logger`:
//  the real `Logger(subsystem: "com.vultisig.app", category: "<feature>.<layer>")`
//  when the category is enabled, or `Logger(.disabled)` when off. Call sites stay
//  100% native OSLog — levels, `\(…, privacy:)` redaction, Console/`log stream`
//  category filtering and signposts are all preserved, because the facade only
//  chooses *which* logger to return; it never wraps the message.
//
//  Usage (declaration-swap only, at spoke-migration time):
//      private let logger = Log.swap.service
//      logger.error("failed \(id, privacy: .public)")   // unchanged
//
//  Gate:
//    - Compile-time master switch `LOGGING` (present in Debug, absent in Release →
//      `Log.*` compiles down to `Logger(.disabled)`).
//    - Debug-only runtime override via `VULTI_LOG` (Info.plist default → scheme env
//      var → UserDefaults), resolved by `LogConfig`.
//
//  Enforcement boundary: because A1 hands back an *unwrapped* `os.Logger` (so native
//  interpolation and `\(…, privacy:)` survive), the gate enforces a category's
//  ON/OFF state — `.off` yields `Logger(.disabled)`, any real level yields the live
//  logger. A `VULTI_LOG` level (`swap:warning`) is the recorded *minimum level* for
//  that category: it drives Console/`log stream` filtering and is exposed via
//  `LogConfig.isEnabled(_:_:_:)` for opt-in level-aware call paths, but a single live
//  `os.Logger` is intentionally not per-level filtered in-process (that would require
//  wrapping the message and flattening privacy).
//

import Foundation
import OSLog
import os

/// Namespace + entry point for the logging facade.
enum Log {
    /// The single OSLog subsystem for the whole app.
    static let subsystem = "com.vultisig.app"

    /// The composed OSLog category `"<feature>.<layer>"` — the string Console and
    /// `log stream` filter on (`category BEGINSWITH "swap"` / `ENDSWITH ".network"`).
    static func category(_ feature: LogFeature, _ layer: LogLayer) -> String {
        "\(feature.rawValue).\(layer.rawValue)"
    }

    static var keygen: FeatureLog { FeatureLog(.keygen) }
    static var keysign: FeatureLog { FeatureLog(.keysign) }
    static var tss: FeatureLog { FeatureLog(.tss) }
    static var swap: FeatureLog { FeatureLog(.swap) }
    static var send: FeatureLog { FeatureLog(.send) }
    static var defi: FeatureLog { FeatureLog(.defi) }
    static var qbtc: FeatureLog { FeatureLog(.qbtc) }
    static var chain: FeatureLog { FeatureLog(.chain) }
    static var wallet: FeatureLog { FeatureLog(.wallet) }
    static var app: FeatureLog { FeatureLog(.app) }

    /// Escape hatch for a dynamically chosen feature.
    static func feature(_ feature: LogFeature) -> FeatureLog { FeatureLog(feature) }
}

/// A feature's layer accessors. Each property resolves the configured `Logger` for
/// `(feature, layer)` through `LogGate`, so it honours the compile-time and runtime gate.
struct FeatureLog {
    let feature: LogFeature

    fileprivate init(_ feature: LogFeature) { self.feature = feature }

    var service: Logger { LogGate.logger(feature, .service) }
    var viewModel: Logger { LogGate.logger(feature, .viewModel) }
    var interactor: Logger { LogGate.logger(feature, .interactor) }
    var network: Logger { LogGate.logger(feature, .network) }
    var view: Logger { LogGate.logger(feature, .view) }
    var tss: Logger { LogGate.logger(feature, .tss) }
    var store: Logger { LogGate.logger(feature, .store) }
    var other: Logger { LogGate.logger(feature, .other) }

    /// Escape hatch for a dynamically chosen layer.
    subscript(_ layer: LogLayer) -> Logger { LogGate.logger(feature, layer) }
}

/// Resolves `(feature, layer)` to a configured `os.Logger`, applying the gate.
///
/// - In Release (no `LOGGING` flag) every lookup compiles to `Logger(.disabled)`;
///   the config machinery is stripped entirely.
/// - In Debug (`LOGGING` present) the current `LogConfig` snapshot decides real vs
///   disabled per category. The snapshot is read once at launch and can be swapped
///   (e.g. by tests) under a lock.
enum LogGate {
#if LOGGING
    /// Thread-safe current config snapshot. Resolved lazily on first use.
    private static let state = OSAllocatedUnfairLock(initialState: LogConfig.resolve())

    /// The active gate snapshot.
    static var config: LogConfig { state.withLock { $0 } }

    /// Replaces the active gate snapshot. Primarily for tests and a future debug toggle screen.
    static func setConfig(_ config: LogConfig) { state.withLock { $0 = config } }

    /// Whether the resolver hands back a live logger (vs `Logger(.disabled)`) for
    /// this category under the current config — the resolver's gate decision.
    static func isEnabled(_ feature: LogFeature, _ layer: LogLayer) -> Bool {
        config.isEnabled(feature, layer)
    }

    static func logger(_ feature: LogFeature, _ layer: LogLayer) -> Logger {
        isEnabled(feature, layer)
            ? Logger(subsystem: Log.subsystem, category: Log.category(feature, layer))
            : Logger(.disabled)
    }
#else
    /// Logging is compiled out in Release: every category is disabled.
    static func isEnabled(_: LogFeature, _: LogLayer) -> Bool { false }

    static func logger(_: LogFeature, _: LogLayer) -> Logger {
        Logger(.disabled)
    }
#endif
}

#if LOGGING
extension LogConfig {
    /// Resolves the runtime config from the layered sources (last wins):
    /// Info.plist `VultiLogConfig` default → scheme env `VULTI_LOG` → `UserDefaults["VULTI_LOG"]`.
    static func resolve() -> LogConfig {
        LogConfig(parsing: resolveRawString())
    }

    /// The effective `VULTI_LOG` string after applying source precedence.
    static func resolveRawString() -> String {
        var value = ""
        if let plist = Bundle.main.infoDictionary?["VultiLogConfig"] as? String,
           isUsable(plist) {
            value = plist
        }
        if let env = ProcessInfo.processInfo.environment["VULTI_LOG"], isUsable(env) {
            value = env
        }
        if let defaults = UserDefaults.standard.string(forKey: "VULTI_LOG"), isUsable(defaults) {
            value = defaults
        }
        return value
    }

    /// Rejects empty strings and unexpanded build variables (e.g. a literal `$(VULTI_LOG_CONFIG)`).
    private static func isUsable(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !trimmed.contains("$(")
    }
}
#endif
