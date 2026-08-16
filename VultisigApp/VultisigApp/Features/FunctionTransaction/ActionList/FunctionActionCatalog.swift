//
//  FunctionActionCatalog.swift
//  VultisigApp
//
//  Turns "what can I do on this chain?" into `FunctionActionDescriptor`s.
//
//  This is the Functions-side producer of descriptors. The DeFi tab is the
//  other one, and it builds its rows from positions rather than from a chain's
//  case list — which is exactly why the descriptor, not this catalog, is the
//  shared type.
//
//  The single-action rule lives here rather than in a view because it is a
//  property of the *count*, not of any chain: the sibling migrations are
//  changing how many operations each chain offers while this ships, so a
//  hardcoded per-chain count would be wrong within the week.
//

import SwiftUI

enum FunctionActionCatalog {

    /// What the Functions entry point resolves to for a coin.
    enum Entry {
        /// Exactly one operation — the entry point opens it directly. A list
        /// screen with one row is a tap the user should never have to make.
        case action(FunctionActionDescriptor)
        /// Zero or many. Zero is unreachable from the UI (every chain that
        /// offers the entry button offers at least one operation, pinned by
        /// test) but the list renders an empty state rather than a blank page.
        case list([FunctionActionDescriptor])
    }

    /// The coin the actions are resolved against, falling back to the vault's
    /// native coin when none is passed in.
    static func resolveCoin(defaultCoin: Coin?, vault: Vault) -> Coin {
        defaultCoin
            ?? vault.coins.first(where: { $0.isNativeToken })
            ?? Coin.example
    }

    /// Every operation `coin.chain` offers, in the order the chain lists them.
    static func descriptors(for coin: Coin) -> [FunctionActionDescriptor] {
        descriptors(for: coin, types: FunctionCallType.getCases(for: coin))
    }

    /// Descriptors for an explicit set of operations.
    ///
    /// Split out so the passthrough rule can be exercised against case lists
    /// that no chain has *yet* — the interesting one being a chain whose only
    /// operation has already been migrated, which the previous
    /// selection-change seam could not express at all.
    static func descriptors(for coin: Coin, types: [FunctionCallType]) -> [FunctionActionDescriptor] {
        types.map { $0.actionDescriptor(for: coin) }
    }

    static func entry(for coin: Coin) -> Entry {
        entry(descriptors: descriptors(for: coin))
    }

    static func entry(descriptors: [FunctionActionDescriptor]) -> Entry {
        guard descriptors.count == 1, let only = descriptors.first else {
            return .list(descriptors)
        }
        return .action(only)
    }
}

extension FunctionCallType {
    /// The row this operation renders as.
    ///
    /// The destination asks `migratedTransactionType(coin:nodeAddress:)` for
    /// the intent, so "what this operation builds" is stated once for the
    /// whole app. No node address is carried: the list is entered cold, with
    /// no previous form to inherit a pre-fill from.
    ///
    /// Every `FunctionCallType` case is migrated as of the last migration —
    /// there is no legacy screen left to fall back to, so a nil mapping here
    /// is a case that was added without also being wired into
    /// `migratedTransactionType`.
    func actionDescriptor(for coin: Coin) -> FunctionActionDescriptor {
        guard let transactionType = migratedTransactionType(coin: coin, nodeAddress: nil) else {
            preconditionFailure("\(rawValue) has no migrated transaction type and no legacy screen to fall back to")
        }

        return FunctionActionDescriptor(
            id: rawValue,
            title: display(),
            subtitle: actionSubtitle,
            icon: actionIcon,
            destination: .transaction(transactionType)
        )
    }

    /// One line on what the operation does. The dropdown could only ever show
    /// a name, which is why "Custom" needed asking about.
    var actionSubtitle: String {
        switch self {
        case .rebond:
            return "functionActionRebondSubtitle".localized
        case .leave:
            return "functionActionLeaveSubtitle".localized
        case .custom:
            return "functionActionCustomSubtitle".localized
        case .vote:
            return "functionActionVoteSubtitle".localized
        case .cosmosIBC:
            return "functionActionIbcSubtitle".localized
        case .addThorLP:
            return "functionActionAddThorLpSubtitle".localized
        case .withdrawSecuredAsset:
            return "functionActionWithdrawSecuredAssetSubtitle".localized
        }
    }

    var actionIcon: ImageResource {
        switch self {
        case .rebond:
            return .repeat3
        case .leave:
            return .arrowToCornerTopRight
        case .custom:
            return .filePen
        case .vote:
            return .megaphone
        case .cosmosIBC:
            return .connectedDots3
        case .addThorLP:
            return .gridPlus
        case .withdrawSecuredAsset:
            return .circleOpenArrowDown
        }
    }
}
