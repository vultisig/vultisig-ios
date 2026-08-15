//
//  FunctionActionDescriptor.swift
//  VultisigApp
//
//  One operation a user can start, described as data: what to call it, what
//  it does, what it looks like, whether it can be started right now, and
//  where tapping it goes.
//
//  Why a descriptor rather than a screen-shaped enum: producing an intent and
//  navigating is *all* a row does, and two places already want to do exactly
//  that — the chain action list and `DefiChainMainScreen`, whose position
//  cards call `onTransactionToPresent(_:)` with the same
//  `FunctionTransactionType` a `.transaction` destination carries. Keeping the
//  description free of any list-screen concern (no row index, no section, no
//  binding, no navigation of its own) is what lets a DeFi-tab card render the
//  same value later without either producer being rewritten.
//

import SwiftUI

struct FunctionActionDescriptor: Identifiable, Hashable {

    /// Where the row goes. Every operation now has its own screen under
    /// `Features/FunctionTransaction/` — the legacy details screen and its
    /// pre-selected arm were removed with the last migration.
    enum Destination: Hashable {
        /// The intent is enough. A DeFi-tab producer only ever builds this arm.
        case transaction(FunctionTransactionType)
    }

    /// Whether the operation can be started right now.
    ///
    /// Every producer today answers `.available` — the chain catalog offers an
    /// operation or omits it, there is no in-between. The arm exists because
    /// the DeFi tab's rows are position-gated ("nothing bonded to unbond"),
    /// and a renderer that cannot express "shown but not startable" would send
    /// those producers back to bespoke views. The reason string is
    /// user-facing and already localized.
    enum Availability: Hashable {
        case available
        case unavailable(reason: String)
    }

    /// Stable across rebuilds so SwiftUI keeps row identity; unique within one
    /// producer's output.
    let id: String
    /// Localized. What the operation is called.
    let title: String
    /// Localized. One line on what the operation does, or `nil` when the title
    /// says everything.
    let subtitle: String?
    let icon: ImageResource
    let availability: Availability
    let destination: Destination

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        icon: ImageResource,
        availability: Availability = .available,
        destination: Destination
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.availability = availability
        self.destination = destination
    }

    var isAvailable: Bool {
        switch availability {
        case .available:
            return true
        case .unavailable:
            return false
        }
    }

    /// The reason an unavailable action cannot be started, for renderers that
    /// show it in place of the subtitle.
    var unavailableReason: String? {
        switch availability {
        case .available:
            return nil
        case .unavailable(let reason):
            return reason
        }
    }
}
