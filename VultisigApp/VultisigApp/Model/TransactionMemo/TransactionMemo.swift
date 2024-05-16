import SwiftUI
import Foundation
import Combine

enum TransactionMemoType: String, CaseIterable, Identifiable {
    case swap, depositSavers, withdrawSavers, openLoan, repayLoan, addLiquidity, withdrawLiquidity, addTradeAccount, withdrawTradeAccount, nodeMaintenance, donateReserve, migrate
    
    var id: String { self.rawValue }
}

enum TransactionContractType: String, CaseIterable, Identifiable {
    case thorChainMessageDeposit
    
    var id: String { self.rawValue }
}

protocol Addressable: ObservableObject {
    var addressFields: [String: String] { get set }
    func getView() -> AnyView
}

class TransactionMemoSwap: Addressable, ObservableObject {
    @Published var asset: String = ""
    @Published var destinationAddress: String = ""
    @Published var limit: Double = 0.0
    @Published var interval: Int = 0
    @Published var quantity: Int = 0
    @Published var affiliate: String = ""
    @Published var fee: Double = 0.0
    
    var addressFields: [String: String] {
        get { ["destinationAddress": destinationAddress] }
        set { if let value = newValue["destinationAddress"] { destinationAddress = value } }
    }
    
    required init() {}
    
    init(asset: String, destinationAddress: String, limit: Double, interval: Int, quantity: Int, affiliate: String = "", fee: Double) {
        self.asset = asset
        self.destinationAddress = destinationAddress
        self.limit = limit
        self.interval = interval
        self.quantity = quantity
        self.affiliate = affiliate
        self.fee = fee
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        var memo = "SWAP:\(self.asset):\(self.destinationAddress)"
        if self.limit != 0.0 {
            memo += ":\(self.limit)"
            if self.interval != 0 && self.quantity != 0 {
                memo += "/\(self.interval)/\(self.quantity)"
            }
        }
        if !self.affiliate.isEmpty && self.fee != 0.0 {
            memo += ":\(affiliate):\(fee)"
        }
        return memo
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            StyledTextField(placeholder: "Asset", text: Binding(
                get: { self.asset },
                set: { self.asset = $0 }
            ))
            TransactionMemoAddressTextField(memo: self, addressKey: "destinationAddress")
            StyledFloatingPointField(placeholder: "Limit", value: Binding(
                get: { self.limit },
                set: { self.limit = $0 }
            ), format: .number)
            StyledIntegerField(placeholder:"Interval", value: Binding(
                get: { self.interval },
                set: { self.interval = $0 }
            ), format: .number)
            StyledIntegerField(placeholder:"Quantity", value: Binding(
                get: { self.quantity },
                set: { self.quantity = $0 }
            ), format: .number)
            StyledTextField(placeholder:"Affiliate", text: Binding(
                get: { self.affiliate },
                set: { self.affiliate = $0 }
            ))
            StyledFloatingPointField(placeholder:"Fee", value: Binding(
                get: { self.fee },
                set: { self.fee = $0 }
            ), format: .number)
        })
    }
}
class TransactionMemoDepositSavers: Addressable, ObservableObject {
    @Published var pool: String = ""
    @Published var affiliate: String = ""
    @Published var fee: Double = 0.0
    
    var addressFields: [String: String] {
        get { [:] }
        set { }
    }
    
    required init() {}
    
    init(pool: String, affiliate: String = "", fee: Double = 0.0) {
        self.pool = pool
        self.affiliate = affiliate
        self.fee = fee
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        var memo = "DEPOSIT:\(self.pool)"
        if !self.affiliate.isEmpty && self.fee != 0.0 {
            memo += ":\(affiliate):\(fee)"
        }
        return memo
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            StyledTextField(placeholder: "Pool", text: Binding(
                get: { self.pool },
                set: { self.pool = $0 }
            ))
            StyledTextField(placeholder: "Affiliate", text: Binding(
                get: { self.affiliate },
                set: { self.affiliate = $0 }
            ))
            StyledFloatingPointField(placeholder: "Fee", value: Binding(
                get: { self.fee },
                set: { self.fee = $0 }
            ), format: .number)
        })
    }
}

class TransactionMemoWithdrawSavers: Addressable, ObservableObject {
    @Published var pool: String = ""
    @Published var basisPoints: Int = 0
    
    var addressFields: [String: String] {
        get { [:] }
        set { }
    }
    
    required init() {}
    
    init(pool: String, basisPoints: Int) {
        self.pool = pool
        self.basisPoints = basisPoints
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        "WITHDRAW:\(self.pool):\(self.basisPoints)"
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            StyledTextField(placeholder: "Pool", text: Binding(
                get: { self.pool },
                set: { self.pool = $0 }
            ))
            StyledIntegerField(placeholder: "Basis Points", value: Binding(
                get: { self.basisPoints },
                set: { self.basisPoints = $0 }
            ), format: .number)
        })
    }
}

class TransactionMemoOpenLoan: Addressable, ObservableObject {
    @Published var asset: String = ""
    @Published var destinationAddress: String = ""
    @Published var minOut: Double = 0.0
    @Published var affiliate: String = ""
    @Published var fee: Double = 0.0
    
    var addressFields: [String: String] {
        get { ["destinationAddress": destinationAddress] }
        set { if let value = newValue["destinationAddress"] { destinationAddress = value } }
    }
    
    required init() {}
    
    init(asset: String, destinationAddress: String, minOut: Double, affiliate: String = "", fee: Double = 0.0) {
        self.asset = asset
        self.destinationAddress = destinationAddress
        self.minOut = minOut
        self.affiliate = affiliate
        self.fee = fee
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        var memo = "LOAN+:\(self.asset):\(self.destinationAddress):\(self.minOut)"
        if !self.affiliate.isEmpty && self.fee != 0.0 {
            memo += ":\(affiliate):\(fee)"
        }
        return memo
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            StyledTextField(placeholder: "Asset", text: Binding(
                get: { self.asset },
                set: { self.asset = $0 }
            ))
            TransactionMemoAddressTextField(memo: self, addressKey: "destinationAddress")
            StyledFloatingPointField(placeholder: "Min Out", value: Binding(
                get: { self.minOut },
                set: { self.minOut = $0 }
            ), format: .number)
            StyledTextField(placeholder: "Affiliate", text: Binding(
                get: { self.affiliate },
                set: { self.affiliate = $0 }
            ))
            StyledFloatingPointField(placeholder: "Fee", value: Binding(
                get: { self.fee },
                set: { self.fee = $0 }
            ), format: .number)
        })
    }
}

class TransactionMemoRepayLoan: Addressable, ObservableObject {
    @Published var asset: String = ""
    @Published var destinationAddress: String = ""
    @Published var minOut: Double = 0.0
    
    var addressFields: [String: String] {
        get { ["destinationAddress": destinationAddress] }
        set { if let value = newValue["destinationAddress"] { destinationAddress = value } }
    }
    
    required init() {}
    
    init(asset: String, destinationAddress: String, minOut: Double) {
        self.asset = asset
        self.destinationAddress = destinationAddress
        self.minOut = minOut
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        "LOAN-:\(self.asset):\(self.destinationAddress):\(self.minOut)"
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            StyledTextField(placeholder: "Asset", text: Binding(
                get: { self.asset },
                set: { self.asset = $0 }
            ))
            TransactionMemoAddressTextField(memo: self, addressKey: "destinationAddress")
            StyledFloatingPointField(placeholder: "Min Out", value: Binding(
                get: { self.minOut },
                set: { self.minOut = $0 }
            ), format: .number)
        })
    }
}

class TransactionMemoAddLiquidity: Addressable, ObservableObject {
    @Published var pool: String = ""
    @Published var pairedAddress: String = ""
    @Published var affiliate: String = ""
    @Published var fee: Double = 0.0
    
    var addressFields: [String: String] {
        get { ["pairedAddress": pairedAddress] }
        set { if let value = newValue["pairedAddress"] { pairedAddress = value } }
    }
    
    required init() {}
    
    init(pool: String, pairedAddress: String = "", affiliate: String = "", fee: Double = 0.0) {
        self.pool = pool
        self.pairedAddress = pairedAddress
        self.affiliate = affiliate
        self.fee = fee
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        var memo = "ADD:\(self.pool)"
        if !self.pairedAddress.isEmpty {
            memo += ":\(pairedAddress)"
        }
        if !self.affiliate.isEmpty && self.fee != 0.0 {
            memo += ":\(affiliate):\(fee)"
        }
        return memo
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            StyledTextField(placeholder: "Pool", text: Binding(
                get: { self.pool },
                set: { self.pool = $0 }
            ))
            TransactionMemoAddressTextField(memo: self, addressKey: "pairedAddress")
            StyledTextField(placeholder: "Affiliate", text: Binding(
                get: { self.affiliate },
                set: { self.affiliate = $0 }
            ))
            StyledFloatingPointField(placeholder: "Fee", value: Binding(
                get: { self.fee },
                set: { self.fee = $0 }
            ), format: .number)
        })
    }
}

class TransactionMemoWithdrawLiquidity: Addressable, ObservableObject {
    @Published var pool: String = ""
    @Published var basisPoints: Int = 0
    @Published var asset: String = ""
    
    var addressFields: [String: String] {
        get { [:] }
        set { }
    }
    
    required init() {}
    
    init(pool: String, basisPoints: Int, asset: String = "") {
        self.pool = pool
        self.basisPoints = basisPoints
        self.asset = asset
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        var memo = "WITHDRAW:\(self.pool):\(self.basisPoints)"
        if !self.asset.isEmpty {
            memo += ":\(asset)"
        }
        return memo
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            StyledTextField(placeholder: "Pool", text: Binding(
                get: { self.pool },
                set: { self.pool = $0 }
            ))
            StyledIntegerField(placeholder: "Basis Points", value: Binding(
                get: { self.basisPoints },
                set: { self.basisPoints = $0 }
            ), format: .number)
            StyledTextField(placeholder: "Asset", text: Binding(
                get: { self.asset },
                set: { self.asset = $0 }
            ))
        })
    }
}

class TransactionMemoAddTradeAccount: Addressable, ObservableObject {
    @Published var address: String = ""
    
    var addressFields: [String: String] {
        get { ["address": address] }
        set { if let value = newValue["address"] { address = value } }
    }
    
    required init() {}
    
    init(address: String) {
        self.address = address
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        "TRADE+:\(self.address)"
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            TransactionMemoAddressTextField(memo: self, addressKey: "address")
        })
    }
}

class TransactionMemoWithdrawTradeAccount: Addressable, ObservableObject {
    @Published var address: String = ""
    
    var addressFields: [String: String] {
        get { ["address": address] }
        set { if let value = newValue["address"] { address = value } }
    }
    
    required init() {}
    
    init(address: String) {
        self.address = address
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        "TRADE-:\(self.address)"
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            TransactionMemoAddressTextField(memo: self, addressKey: "address")
        })
    }
}

class TransactionMemoNodeMaintenance: Addressable, ObservableObject {
    @Published var nodeAddress: String = ""
    @Published var provider: String = ""
    @Published var fee: Double = 0.0
    @Published var amount: Double = 0.0
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
    
    required init() {}
    
    init(nodeAddress: String, provider: String = "", fee: Double = 0.0, amount: Double = 0.0, action: NodeAction = .bond) {
        self.nodeAddress = nodeAddress
        self.provider = provider
        self.fee = fee
        self.amount = amount
        self.action = action
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
        if !self.provider.isEmpty && self.fee != 0.0 {
            memo += ":\(provider):\(fee)"
        }
        return memo
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            TransactionMemoAddressTextField(memo: self, addressKey: "nodeAddress")
            TransactionMemoAddressTextField(memo: self, addressKey: "provider")
            StyledFloatingPointField(placeholder: "Fee", value: Binding(
                get: { self.fee },
                set: { self.fee = $0 }
            ), format: .number)
            StyledFloatingPointField(placeholder: "Amount", value: Binding(
                get: { self.amount },
                set: { self.amount = $0 }
            ), format: .number)
            Picker("Action", selection: Binding(
                get: { self.action },
                set: { self.action = $0 }
            )) {
                Text("Bond").tag(NodeAction.bond)
                Text("Unbond").tag(NodeAction.unbond)
                Text("Leave").tag(NodeAction.leave)
            }
        })
    }
}

class TransactionMemoDonateReserve: Addressable, ObservableObject {
    @Published var pool: String = ""
    
    var addressFields: [String: String] {
        get { [:] }
        set { }
    }
    
    required init() {}
    
    init(pool: String = "") {
        self.pool = pool
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        guard !self.pool.isEmpty else {
            return "RESERVE"
        }
        return "DONATE:\(pool)"
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            StyledTextField(placeholder: "Pool", text: Binding(
                get: { self.pool },
                set: { self.pool = $0 }
            ))
        })
    }
}

class TransactionMemoMigrate: Addressable, ObservableObject {
    @Published var blockHeight: Int = 0
    
    var addressFields: [String: String] {
        get { [:] }
        set { }
    }
    
    required init() {}
    
    init(blockHeight: Int) {
        self.blockHeight = blockHeight
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        "MIGRATE:\(self.blockHeight)"
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            StyledIntegerField(placeholder: "Block Height", value: Binding(
                get: { self.blockHeight },
                set: { self.blockHeight = $0 }
            ), format: .number)
        })
    }
}

enum TransactionMemoInstance {
    case swap(TransactionMemoSwap)
    case depositSavers(TransactionMemoDepositSavers)
    case withdrawSavers(TransactionMemoWithdrawSavers)
    case openLoan(TransactionMemoOpenLoan)
    case repayLoan(TransactionMemoRepayLoan)
    case addLiquidity(TransactionMemoAddLiquidity)
    case withdrawLiquidity(TransactionMemoWithdrawLiquidity)
    case addTradeAccount(TransactionMemoAddTradeAccount)
    case withdrawTradeAccount(TransactionMemoWithdrawTradeAccount)
    case nodeMaintenance(TransactionMemoNodeMaintenance)
    case donateReserve(TransactionMemoDonateReserve)
    case migrate(TransactionMemoMigrate)
    
    var view: AnyView {
        switch self {
        case .swap(let memo):
            return memo.getView()
        case .depositSavers(let memo):
            return memo.getView()
        case .withdrawSavers(let memo):
            return memo.getView()
        case .openLoan(let memo):
            return memo.getView()
        case .repayLoan(let memo):
            return memo.getView()
        case .addLiquidity(let memo):
            return memo.getView()
        case .withdrawLiquidity(let memo):
            return memo.getView()
        case .addTradeAccount(let memo):
            return memo.getView()
        case .withdrawTradeAccount(let memo):
            return memo.getView()
        case .nodeMaintenance(let memo):
            return memo.getView()
        case .donateReserve(let memo):
            return memo.getView()
        case .migrate(let memo):
            return memo.getView()
        }
    }
    
    var description: String {
        switch self {
        case .swap(let memo):
            return memo.description
        case .depositSavers(let memo):
            return memo.description
        case .withdrawSavers(let memo):
            return memo.description
        case .openLoan(let memo):
            return memo.description
        case .repayLoan(let memo):
            return memo.description
        case .addLiquidity(let memo):
            return memo.description
        case .withdrawLiquidity(let memo):
            return memo.description
        case .addTradeAccount(let memo):
            return memo.description
        case .withdrawTradeAccount(let memo):
            return memo.description
        case .nodeMaintenance(let memo):
            return memo.description
        case .donateReserve(let memo):
            return memo.description
        case .migrate(let memo):
            return memo.description
        }
    }
}
