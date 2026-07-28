//
//  LogLayer.swift
//  VultisigApp
//
//  Layer axis of the logging taxonomy. Combined with `LogFeature` it forms the
//  OSLog category `"<feature>.<layer>"`. The rawValue is the category suffix, so
//  `category ENDSWITH ".network"` filters the transport layer across all features.
//
//  Cases are derived from the category suffix/prefix survey (see wiki
//  `logging-wrapper/analysis.md`): `*-service`→service, `*-vm`/`*-view-model`→viewModel,
//  `*-interactor`→interactor, `net-*`/`communication`/`*-messenger`→network,
//  `*-screen`/`*-view`/`*-row`→view, `*-store`/`*-storage`/`*-cache`→store,
//  `tss`→tss, everything else (signers, helpers, resolvers, decoders)→other.
//

import Foundation

/// The architectural layer used as the second segment of an OSLog category.
enum LogLayer: String, CaseIterable, Sendable {
    /// Data / network service objects (`*-service`).
    case service
    /// View models (`*-vm`, `*-view-model`, `viewmodel`).
    case viewModel
    /// Feature interactors (`*-interactor`).
    case interactor
    /// MPC / peer-discovery transport (`net-*`, `communication`, `*-messenger`).
    case network
    /// SwiftUI views, screens, rows and animations (`*-screen`, `*-view`, `*-row`).
    case view
    /// TSS / MPC orchestration layer (`tss`).
    case tss
    /// Persistence, caches and stores (`*-store`, `*-storage`, `*-cache`).
    case store
    /// Signers, helpers, resolvers, decoders and other utilities that don't fit a specific layer.
    case other
}
