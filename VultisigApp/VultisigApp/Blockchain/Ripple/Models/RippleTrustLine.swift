//
//  RippleTrustLine.swift
//  VultisigApp
//

import Foundation

/// One XRPL trust line as returned by `account_lines`, always from the
/// perspective of the account the request was made for.
/// - https://xrpl.org/docs/references/http-websocket-apis/public-api-methods/account-methods/account_lines
struct RippleTrustLine: Decodable, Equatable {
    /// The **counterparty** of the line. XRPL names the field `account` even
    /// though it is never the requested account — for a token the requested
    /// account holds, this is the issuer.
    let account: String

    /// Signed value string in the line's currency. A NEGATIVE balance means the
    /// requested account is the line's issuer and owes the counterparty, so it
    /// is a liability rather than a holding.
    let balance: String

    /// On-ledger currency code: a 3-character standard code (`USD`) or the
    /// 40-character (160-bit) hex form.
    let currency: String

    /// The maximum amount of `currency` the requested account is willing to owe
    /// the counterparty — the trust-line limit. Decoded but not yet consumed;
    /// the add-token / TrustSet flow needs it.
    let limit: String?

    /// `NoRipple` flag the requested account set on this line.
    let noRipple: Bool?

    /// Whether the requested account has frozen this line.
    let freeze: Bool?

    enum CodingKeys: String, CodingKey {
        case account
        case balance
        case currency
        case limit
        case noRipple = "no_ripple"
        case freeze
    }
}

/// Failures specific to reading trust lines. Technical, developer-facing copy in
/// the same style as `RippleBroadcastError`: these only ever reach logs and the
/// balance-refresh warning path, never user-facing UI.
enum RippleTrustLineError: Error, LocalizedError {
    /// `account_lines` answered with a non-retryable node error other than
    /// `actNotFound`. Surfaced rather than degraded to an empty line set, so a
    /// malformed request or an unsupported backend can never be rendered as a
    /// zero token balance.
    case accountLinesFailed(code: String)

    /// An HTTP-200 body that carried neither a `lines` array nor a node error —
    /// a proxy error page, a truncated body, an unexpected shape. A successful
    /// `account_lines` always returns `lines` (empty for an account that holds
    /// none), so an absent array is NOT an empty wallet: reading it as one would
    /// render a real token balance as zero. Fails closed instead, matching
    /// `validateDestinationActivation`'s posture on an uninterpretable
    /// `account_info` reply.
    case malformedResponse

    /// Pagination did not terminate within the page budget — either an account
    /// with an implausible number of lines, or a backend echoing the same
    /// marker forever.
    case paginationLimitExceeded(pages: Int)

    var errorDescription: String? {
        switch self {
        case .accountLinesFailed(let code):
            return "XRPL account_lines failed (\(code))"
        case .malformedResponse:
            return "XRPL account_lines returned no trust-line array and no error"
        case .paginationLimitExceeded(let pages):
            return "XRPL account_lines pagination exceeded \(pages) pages"
        }
    }
}
