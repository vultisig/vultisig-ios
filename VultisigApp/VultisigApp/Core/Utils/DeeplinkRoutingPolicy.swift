//
//  DeeplinkRoutingPolicy.swift
//  VultisigApp
//

import Foundation

/// Decides what a link that did not come from this app's own scanner may do.
enum DeeplinkRoutingPolicy {
    private static let keysignType = "SignTransaction"
    private static let keygenType = "NewVault"

    /// Devices only ever push keysign requests, but the push backend relays
    /// whatever payload it is handed. Anything that is not a keysign link is
    /// dropped, because following a keygen link would join a ceremony the user
    /// never started.
    static func allowsPushNotificationRoute(_ url: URL) -> Bool {
        guard let components = URLComponents(string: url.absoluteString),
              components.host?.lowercased() != "send",
              !components.path.lowercased().contains("send") else {
            return false
        }
        return queryValue("type", in: components) == keysignType
    }

    /// An externally opened link that would start or join a keygen / reshare
    /// session. These must not run until the user confirms.
    static func requiresJoinConfirmation(_ url: URL) -> Bool {
        guard let components = URLComponents(string: url.absoluteString),
              components.queryItems != nil else {
            return false
        }
        let type = queryValue("type", in: components)
        if type == keygenType { return true }
        return type != keysignType && queryValue("jsonData", in: components) != nil
    }

    private static func queryValue(_ name: String, in components: URLComponents) -> String? {
        components.queryItems?.first(where: { $0.name == name })?.value
    }
}
