//
//  HumanDecimalAmountValidator.swift
//  VultisigApp
//

/// Refuses text `HumanDecimalAmount.parse` would refuse, so a form that builds from
/// `parse` shows "invalid amount" instead of a Continue button that does nothing.
struct HumanDecimalAmountValidator: FormFieldValidator {
    let decimals: Int

    func validate(value: String) throws {
        guard HumanDecimalAmount.parse(value, decimals: decimals) != nil else {
            throw HelperError.runtimeError("invalidAmount".localized)
        }
    }
}
