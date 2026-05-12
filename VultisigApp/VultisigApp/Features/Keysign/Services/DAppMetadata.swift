//
//  DAppMetadata.swift
//  VultisigApp
//

import Foundation

/// Identity of the dApp that produced a keysign request.
///
/// Surfaced in the verify and done screens so signers can see which dApp
/// originated the transaction. Trust decisions stay with Blockaid — this is
/// informational only.
///
/// Mirrors the `DAppMetadata` proto on `KeysignPayload` (commondata#82). Proto
/// strings are non-nullable, so empty strings are treated as missing.
struct DAppMetadata: Codable, Hashable {
    let name: String
    let url: String
    let iconURL: String

    /// Hostname extracted from `url`, falling back to the raw `url` string when
    /// it cannot be parsed (e.g. malformed input from a hostile peer). Empty
    /// strings stay empty so the UI can hide the host segment.
    var host: String {
        if url.isEmpty { return "" }
        if let parsedHost = URL(string: url)?.host, !parsedHost.isEmpty {
            return parsedHost
        }
        return url
    }

    /// True when every field is empty. Use this at the construction boundary to
    /// avoid surfacing meaningless banners to the user.
    var isEmpty: Bool {
        name.isEmpty && url.isEmpty && iconURL.isEmpty
    }
}
