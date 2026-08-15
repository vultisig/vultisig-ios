//
//  IdentifiableString.swift
//  VultisigApp
//
//  A `String` that can back a `ForEach` / `GenericSelectorDropDown` without the
//  caller having to promise the values are unique. Shared by most of the
//  FunctionCall sub-models for their asset and token dropdowns.
//

import Foundation

struct IdentifiableString: Identifiable, Equatable {
    let id = UUID()
    let value: String
}
