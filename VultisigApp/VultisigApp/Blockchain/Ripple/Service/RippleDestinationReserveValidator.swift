//
//  RippleDestinationReserveValidator.swift
//  VultisigApp
//
//  `SendAmountValidator` for native XRP sends: a Payment to an unfunded
//  destination for less than the live base reserve can't create the account,
//  so it's flagged inline (and blocks Continue) one screen before the Verify
//  guard would reject it. Fails open — any lookup it can't complete returns
//  `.ok`, leaving the Verify-screen guard as the fail-closed backstop.
//

import BigInt
import Foundation

struct RippleDestinationReserveValidator: SendAmountValidator {
    private let service: RippleService

    init(service: RippleService = .shared) {
        self.service = service
    }

    /// Preconditions mirror "only when the address is resolved AND an amount is
    /// entered": gating on the address's *format* validity (pure,
    /// side-effect-free) rather than the UI's `addressSetupDone` flag keeps the
    /// lookup from firing against a half-typed destination while the resolver is
    /// still in flight.
    ///
    /// ⚠️ `isNativeToken` is deliberate and must NOT be widened now that
    /// non-native XRP coins exist. The rule is "an account is created by
    /// receiving at least the base reserve **in XRP**"; an issued-currency
    /// Payment delivers no XRP, so it can neither create the destination nor
    /// satisfy that minimum, and applying this check to a token would show an XRP
    /// minimum against an amount denominated in the token. The check that DOES
    /// apply to a token — whether the destination holds a trust line for it —
    /// lives in `SendCryptoVerifyLogic.validateDestinationTrustLineIfNeeded`.
    func isApplicable(to input: SendAmountValidationInput) -> Bool {
        input.chain == .ripple
            && input.isNativeToken
            && !input.toAddress.isEmpty
            && AddressService.validateAddress(address: input.toAddress, chain: input.chain)
            && !input.amount.isEmpty
            && !input.amountDecimal.isZero
    }

    func validate(_ input: SendAmountValidationInput, forceRefresh: Bool) async -> SendAmountValidatorResult {
        guard isApplicable(to: input) else { return .ok }

        let check = await service.destinationReserveShortfall(
            address: input.toAddress,
            amountDrops: input.amountRaw,
            forceRefresh: forceRefresh
        )

        switch check {
        case .belowMinimum(let minimumXRP):
            // Copy is already localized + formatted — render it directly.
            return .invalid(
                message: String(format: "xrpDestinationNotActivatedError".localized, minimumXRP),
                blocksContinue: true
            )
        case .satisfied, .unknown:
            return .ok
        }
    }
}
