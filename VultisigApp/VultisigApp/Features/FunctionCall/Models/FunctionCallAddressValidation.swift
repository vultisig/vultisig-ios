//
//  FunctionCallAddressValidation.swift
//  VultisigApp
//
//  Per-sub-model address-validation helpers — port the multi-chain
//  THOR/MAYA/TON validation that previously lived inside the legacy
//  `FunctionCallAddressTextField.validateAddress(_:)` so individual
//  sub-models can drive their own `addressError` computed properties
//  after the canonical `AddressTextField` migration.
//

import Foundation

enum FunctionCallAddressValidation {
    /// THOR-or-Maya-or-TON multi-chain validity check. Mirrors the
    /// behaviour that used to live inside the legacy
    /// `FunctionCallAddressTextField.validateAddress(_:)` so sub-models
    /// like LEAVE / Unstake / Stake / Maya bond+unbond / ReBond can
    /// surface inline errors without re-binding through the deleted
    /// `FunctionCallAddressable.addressFields` protocol.
    static func isValidThorMayaTON(_ address: String) -> Bool {
        AddressService.validateAddress(address: address, chain: .thorChain) ||
        AddressService.validateAddress(address: address, chain: .mayaChain) ||
        AddressService.validateAddress(address: address, chain: .ton)
    }

    /// Cosmos-chain validity check used by the IBC / Switch flows.
    /// Falls back to the multi-chain THOR/Maya/TON shape when the
    /// caller has no `Chain` context (e.g., before the destination
    /// chain is picked).
    static func isValidCosmos(_ address: String, chain: Chain?) -> Bool {
        guard let chain, chain.chainType == .Cosmos else {
            return isValidThorMayaTON(address)
        }
        return AddressService.validateAddress(address: address, chain: chain)
    }

    /// Returns a non-nil localized error string when the address is
    /// present but does not match the THOR/Maya/TON validators.
    /// Empty-string input intentionally returns `nil` so the field
    /// renders without a red error before the user types anything —
    /// matches the legacy "isAddressValid" gate that only fired after
    /// the field had content.
    static func errorForThorMayaTON(_ address: String) -> String? {
        guard !address.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        return isValidThorMayaTON(address) ? nil : "invalidAddress".localized
    }

    /// Same shape as `errorForThorMayaTON`, but Cosmos-chain aware.
    static func errorForCosmos(_ address: String, chain: Chain?) -> String? {
        guard !address.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        return isValidCosmos(address, chain: chain) ? nil : "invalidAddress".localized
    }
}
