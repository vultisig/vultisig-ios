import SwiftUI
import Foundation
import Combine

class FunctionCallNodeMaintenance: FunctionCallAddressable, ObservableObject {
    @Published var isTheFormValid: Bool = false
    @Published var customErrorMessage: String? = nil
    @Published var isNodeAddressValid: Bool = false
    @Published var isProviderValid: Bool = false
    @Published var isAmountValid: Bool = false
    @Published var isFeeValid: Bool = false

    @Published var nodeAddress: String = ""
    @Published var provider: String = ""
    @Published var fee: Decimal = 0.0
    @Published var amount: Decimal = 0.0
    @Published var action: NodeAction = .bond

    enum NodeAction: String, CaseIterable, Identifiable {
        case bond, unbond, leave
        var id: String { self.rawValue }
    }

    var addressFields: [String: String] {
        get {
            var fields = ["nodeAddress": nodeAddress]
            if !provider.isEmpty {
                fields["provider"] = provider
            }
            return fields
        }
        set {
            if let value = newValue["nodeAddress"] {
                nodeAddress = value
            }
            if let value = newValue["provider"] {
                provider = value
            }
        }
    }

    required init() {
    }

    init(nodeAddress: String, provider: String = "", fee: Decimal = 0.0, amount: Decimal = 0.0, action: NodeAction = .bond) {
        self.nodeAddress = nodeAddress
        self.provider = provider
        self.fee = fee
        self.amount = amount
        self.action = action
        self.isNodeAddressValid = !nodeAddress.isEmpty
        self.isProviderValid = true
        self.isFeeValid = true
        self.isAmountValid = true
        self.isTheFormValid = self.isNodeAddressValid
    }

    var description: String {
        return toString()
    }

    func toString() -> String {
        var memo = ""
        switch self.action {
        case .bond:
            memo = "BOND:\(self.nodeAddress)"
        case .unbond:
            memo = "UNBOND:\(self.nodeAddress):\(self.amount)"
        case .leave:
            memo = "LEAVE:\(self.nodeAddress)"
        }

        if !self.provider.isEmpty {
            memo += ":\(self.provider)"
        }

        if self.fee != 0.0 {
            if self.provider.isEmpty {
                memo += "::\(self.fee)"
            } else {
                memo += ":\(self.fee)"
            }
        }

        return memo
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", "\(self.nodeAddress)")
        dict.set("provider", "\(self.provider)")
        dict.set("fee", "\(self.fee)")
        dict.set("amount", "\(self.amount)")
        dict.set("action", "\(self.action.rawValue)")
        dict.set("memo", self.toString())
        return dict
    }

    func getView() -> AnyView {
        AnyView(VStack {
            FunctionCallAddressTextField(
                memo: self,
                addressKey: "nodeAddress",
                isAddressValid: Binding<Bool>(
                    get: { self.isNodeAddressValid },
                    set: { self.isNodeAddressValid = $0 }
                )
            )
            FunctionCallAddressTextField(
                memo: self,
                addressKey: "provider",
                isOptional: true,
                isAddressValid: Binding<Bool>(
                    get: { self.isProviderValid },
                    set: { self.isProviderValid = $0 }
                )
            )
            StyledFloatingPointField(
                label: "fee".localized,
                placeholder: "fee".localized,
                value: Binding<Decimal>(
                    get: { self.fee },
                    set: { self.fee = $0 }
                ),
                isValid: Binding<Bool>(
                    get: { self.isFeeValid },
                    set: { self.isFeeValid = $0 }
                )
            )
            StyledFloatingPointField(
                label: NSLocalizedString("amount", comment: ""),
                placeholder: NSLocalizedString("enterAmount", comment: ""),
                value: Binding<Decimal>(
                    get: { self.amount },
                    set: { self.amount = $0 }
                ),
                isValid: Binding<Bool>(
                    get: { self.isAmountValid },
                    set: { self.isAmountValid = $0 }
                )
            )

            Picker(selection: Binding(
                get: { self.action },
                set: { self.action = $0 }
            ), label: Text(self.action.rawValue)) {
                Text(NodeAction.bond.rawValue).tag(NodeAction.bond)
                Text(NodeAction.unbond.rawValue).tag(NodeAction.unbond)
                Text(NodeAction.leave.rawValue).tag(NodeAction.leave)
            }

        })
    }
}
