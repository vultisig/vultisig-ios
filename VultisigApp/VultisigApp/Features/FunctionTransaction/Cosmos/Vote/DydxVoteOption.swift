//
//  DydxVoteOption.swift
//  VultisigApp
//
//  The dYdX governance vote options, split into the two things the legacy
//  sub-model conflated: what goes into the memo, and what the user reads.
//
//  The memo token is an English literal here rather than
//  `TW_Cosmos_Proto_Message.VoteOption.description`, which is what the legacy
//  `toString()` interpolated. `description` is a *display* property — the day
//  someone localizes it, a memo derived from it silently changes what is
//  signed. The literals below are the memo; `displayTitle(for:)` is the UI.
//  A test pins that the two still agree today.
//

import Foundation
import WalletCore

enum DydxVoteOption {

    /// The options the form offers, in ballot order.
    ///
    /// Derived from `allCases` rather than listed, so a protobuf update that
    /// adds an option surfaces it here instead of silently dropping it — minus
    /// the ones no chain accepts as a vote.
    static var selectable: [TW_Cosmos_Proto_Message.VoteOption] {
        TW_Cosmos_Proto_Message.VoteOption.allCases.filter(isSubmittable)
    }

    /// Whether an option is a vote at all.
    ///
    /// `.unspecified` is the proto's zero value, meaning "no option set" — the
    /// chain rejects a ballot carrying it, *after* the fee has been spent. The
    /// legacy form offered it (it listed `allCases`) and its validity check
    /// read `rawValue >= 0`, which `.unspecified` satisfies with raw value 0,
    /// so nothing stopped it being submitted. `.UNRECOGNIZED` is an option this
    /// build does not know and cannot name in a memo.
    static func isSubmittable(_ option: TW_Cosmos_Proto_Message.VoteOption) -> Bool {
        switch option {
        case .yes, .abstain, .no, .noWithVeto:
            return true
        case .unspecified, .UNRECOGNIZED:
            return false
        @unknown default:
            return false
        }
    }

    /// The exact token the memo carries for an option, byte for byte what the
    /// legacy sub-model interpolated. `No with Veto` contains spaces; the memo
    /// has always carried them.
    static func memoValue(for option: TW_Cosmos_Proto_Message.VoteOption) -> String {
        switch option {
        case .unspecified:
            return "Unspecified"
        case .yes:
            return "Yes"
        case .abstain:
            return "Abstain"
        case .no:
            return "No"
        case .noWithVeto:
            return "No with Veto"
        case .UNRECOGNIZED(let value):
            return "Unrecognized (\(value))"
        @unknown default:
            return "Unknown"
        }
    }

    /// The submittable option a memo token names, or nil.
    ///
    /// Deliberately answers nil for `Unspecified`: this is what the form's
    /// option validator runs on, so an unsubmittable option cannot round-trip
    /// back into a valid field even if something wrote one there.
    static func option(forMemoValue value: String) -> TW_Cosmos_Proto_Message.VoteOption? {
        selectable.first { memoValue(for: $0) == value }
    }

    /// What the user reads on the row. Localized — unlike the memo token.
    static func displayTitle(for option: TW_Cosmos_Proto_Message.VoteOption) -> String {
        switch option {
        case .yes:
            return "governanceVoteYes".localized
        case .abstain:
            return "governanceVoteAbstain".localized
        case .no:
            return "governanceVoteNo".localized
        case .noWithVeto:
            return "governanceVoteNoWithVeto".localized
        default:
            // Unreachable through `selectable`; falling back to the memo token
            // keeps a hypothetical new option readable rather than blank.
            return memoValue(for: option)
        }
    }
}
