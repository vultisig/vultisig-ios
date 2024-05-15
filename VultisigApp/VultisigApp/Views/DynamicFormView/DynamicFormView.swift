import SwiftUI
import Foundation
import Combine


struct DynamicFormView: View {
    @ObservedObject var viewModel: AnyObservableObject
    
    var body: some View {
        Form {
            ForEach(reflectProperties(of: viewModel.baseObject), id: \.name) { property in
                let name = property.name
                
                // Creating a vertical stack to place the label above the input field
                VStack(alignment: .leading) {
                    Text(name + ":") // This is the label for the input field
                        .fontWeight(.bold) // Optional: Makes the label bold
                    
                    // Place the corresponding input field below the label
                    if let stringBinding = getBinding(for: property, type: String.self) {
                        TextField("Enter \(name)", text: stringBinding)
                    } else if let doubleBinding = getBinding(for: property, type: Double.self) {
                        TextField("Enter \(name)", value: doubleBinding, formatter: NumberFormatter())
                    } else if let intBinding = getBinding(for: property, type: Int.self) {
                        TextField("Enter \(name)", value: intBinding, formatter: NumberFormatter())
                    }
                }
            }
            
            // Submit button to print the .toString() result
            Button("Submit") {
                // Action to perform when button is clicked
                printModelDescription()
            }
            .frame(maxWidth: .infinity, alignment: .center) // Centers the button in the form
        }
    }
    
    // Function to print the .toString() of the view model's base object
    private func printModelDescription() {
        if let model = viewModel.baseObject as? CustomStringConvertible {
            print(model.description)
        } else {
            print("Model does not conform to CustomStringConvertible.")
        }
    }
    
    
    func reflectProperties(of instance: Any) -> [(name: String, value: Any)] {
        let mirror = Mirror(reflecting: instance)
        return mirror.children.compactMap { child in
            if let label = child.label {
                return (name: label, value: child.value)
            }
            return nil
        }
    }
    
    
    func createBinding<Value>(from propertyValue: Any, propertyName: String) -> Binding<Value>? {
        return Binding<Value>(
            get: {
                // Retrieve the value using key-value coding
                if let base = viewModel.baseObject as? NSObject,
                   let value = base.value(forKeyPath: propertyName) as? Value {
                    return value
                }
                // Handle direct access to Published value
                if let published = Mirror(reflecting: propertyValue).descendant("storage", "subject", "value") as? Value {
                    return published
                }
                // Handle optional value stored in Published
                if let publishedOptional = Mirror(reflecting: propertyValue).descendant("storage", "subject", "value") as? Value? {
                    return publishedOptional ?? fallbackValue(for: Value.self)
                }
                fatalError("Unable to access Published value for property: \(propertyName)")
            },
            set: { newValue in
                print(newValue)
                if let base = viewModel.baseObject as? NSObject {
                    base.setValue(newValue, forKey: propertyName)
                }
                // Update the subject with new value
                if let subject = Mirror(reflecting: propertyValue).descendant("storage", "subject") as? CurrentValueSubject<Value, Never> {
                    subject.send(newValue)
                } else if let optionalSubject = Mirror(reflecting: propertyValue).descendant("storage", "subject") as? CurrentValueSubject<Value?, Never> {
                    optionalSubject.send(newValue)
                }
            }
        )
    }
    
    // Add a helper function to provide a fallback value when necessary
    func fallbackValue<Value>(for type: Value.Type) -> Value {
        switch type {
        case is Int.Type:
            return 0 as! Value
        case is Double.Type:
            return 0.0 as! Value
        case is String.Type:
            return "" as! Value
        default:
            fatalError("No fallback value available for type \(type)")
        }
    }
    
    
    // Adjust how you use createBinding in getBinding function
    func getBinding<Value>(for property: (name: String, value: Any), type: Value.Type) -> Binding<Value>? {
        let propertyName = property.name
        let propertyValue = property.value
        // Call createBinding with proper handling for optional Published values
        if let publishedValue = propertyValue as? Published<Value> {
            return createBinding(from: publishedValue, propertyName: propertyName)
        } else if let publishedOptionalValue = propertyValue as? Published<Value?> {
            return createBinding(from: publishedOptionalValue, propertyName: propertyName)
        }
        return nil
    }
    
    
    
    
    
    
    
    
}

class AnyObservableObject: ObservableObject {
    private let _objectWillChange: AnyPublisher<Void, Never>
    private let base: AnyObject
    
    init<T: ObservableObject>(_ base: T) {
        self.base = base
        _objectWillChange = base.objectWillChange
            .map { _ in () }
            .catch { _ in Just(()) }
            .eraseToAnyPublisher()
    }
    
    var objectWillChange: AnyPublisher<Void, Never> {
        _objectWillChange
    }
    
    var baseObject: AnyObject {
        return base
    }
}


enum TransactionMemoType: String, CaseIterable, Identifiable {
    case swap, depositSavers, withdrawSavers, openLoan, repayLoan, addLiquidity, withdrawLiquidity, addTradeAccount, withdrawTradeAccount, nodeMaintenance, donateReserve, migrate, noop
    
    var id: String { self.rawValue }
    
    func viewModel() -> AnyObservableObject {
        switch self {
        case .swap:
            return AnyObservableObject(TransactionMemoSwap(asset: "", destinationAddress: "", limit: nil, interval: nil, quantity: nil, affiliate: nil, fee: nil))
        case .depositSavers:
            return AnyObservableObject(TransactionMemoDepositSavers(pool: "", affiliate: nil, fee: nil))
        case .withdrawSavers:
            return AnyObservableObject(TransactionMemoWithdrawSavers(pool: "", basisPoints: 0))
        case .openLoan:
            return AnyObservableObject(TransactionMemoOpenLoan(asset: "", destinationAddress: "", minOut: 0.0, affiliate: nil, fee: nil))
        case .repayLoan:
            return AnyObservableObject(TransactionMemoRepayLoan(asset: "", destinationAddress: "", minOut: 0.0))
        case .addLiquidity:
            return AnyObservableObject(TransactionMemoAddLiquidity(pool: "", pairedAddress: nil, affiliate: nil, fee: nil))
        case .withdrawLiquidity:
            return AnyObservableObject(TransactionMemoWithdrawLiquidity(pool: "", basisPoints: 0, asset: nil))
        case .addTradeAccount:
            return AnyObservableObject(TransactionMemoAddTradeAccount(address: ""))
        case .withdrawTradeAccount:
            return AnyObservableObject(TransactionMemoWithdrawTradeAccount(address: ""))
        case .nodeMaintenance:
            return AnyObservableObject(TransactionMemoNodeMaintenance(nodeAddress: "", provider: nil, fee: nil, amount: nil, action: .bond))
        case .donateReserve:
            return AnyObservableObject(TransactionMemoDonateReserve(pool: nil))
        case .migrate:
            return AnyObservableObject(TransactionMemoMigrate(blockHeight: 0))
        case .noop:
            return AnyObservableObject(NoOp())
        }
    }
}

// MARK: - SWAP
class TransactionMemoSwap: ObservableObject, CustomStringConvertible {
    @Published var asset: String
    @Published var destinationAddress: String
    @Published var limit: Double?
    @Published var interval: Int?
    @Published var quantity: Int?
    @Published var affiliate: String?
    @Published var fee: Double?
    
    init(asset: String, destinationAddress: String, limit: Double?, interval: Int?, quantity: Int?, affiliate: String?, fee: Double?) {
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
        if let limit = self.limit {
            memo += ":\(limit)"
            if let interval = self.interval, let quantity = self.quantity {
                memo += "/\(interval)/\(quantity)"
            }
        }
        if let affiliate = self.affiliate, let fee = self.fee {
            memo += ":\(affiliate):\(fee)"
        }
        return memo
    }
}

// MARK: - DEPOSIT Savers
class TransactionMemoDepositSavers: ObservableObject, CustomStringConvertible {
    @Published var pool: String
    @Published var affiliate: String?
    @Published var fee: Double?
    
    init(pool: String, affiliate: String?, fee: Double?) {
        self.pool = pool
        self.affiliate = affiliate
        self.fee = fee
    }
    var description: String {
        return toString()
    }
    func toString() -> String {
        var memo = "DEPOSIT:\(self.pool)"
        if let affiliate = self.affiliate, let fee = self.fee {
            memo += ":\(affiliate):\(fee)"
        }
        return memo
    }
}

// MARK: - WITHDRAW Savers
class TransactionMemoWithdrawSavers: ObservableObject, CustomStringConvertible {
    @Published var pool: String
    @Published var basisPoints: Int
    
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
}

// MARK: - OPEN Loan
class TransactionMemoOpenLoan: ObservableObject, CustomStringConvertible {
    @Published var asset: String
    @Published var destinationAddress: String
    @Published var minOut: Double
    @Published var affiliate: String?
    @Published var fee: Double?
    
    init(asset: String, destinationAddress: String, minOut: Double, affiliate: String?, fee: Double?) {
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
        if let affiliate = self.affiliate, let fee = self.fee {
            memo += ":\(affiliate):\(fee)"
        }
        return memo
    }
}

// MARK: - REPAY Loan
class TransactionMemoRepayLoan: ObservableObject, CustomStringConvertible {
    @Published var asset: String
    @Published var destinationAddress: String
    @Published var minOut: Double
    
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
}

// MARK: - ADD Liquidity
class TransactionMemoAddLiquidity: ObservableObject, CustomStringConvertible {
    @Published var pool: String
    @Published var pairedAddress: String?
    @Published var affiliate: String?
    @Published var fee: Double?
    
    init(pool: String, pairedAddress: String?, affiliate: String?, fee: Double?) {
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
        if let pairedAddress = self.pairedAddress {
            memo += ":\(pairedAddress)"
        }
        if let affiliate = self.affiliate, let fee = self.fee {
            memo += ":\\(affiliate):\(fee)"
        }
        return memo
    }
}

// MARK: - WITHDRAW Liquidity
class TransactionMemoWithdrawLiquidity: ObservableObject, CustomStringConvertible {
    @Published var pool: String
    @Published var basisPoints: Int
    @Published var asset: String?
    
    init(pool: String, basisPoints: Int, asset: String?) {
        self.pool = pool
        self.basisPoints = basisPoints
        self.asset = asset
    }
    var description: String {
        return toString()
    }
    func toString() -> String {
        var memo = "WITHDRAW:\(self.pool):\(self.basisPoints)"
        if let assetString = self.asset {
            memo += ":\(assetString)"
        }
        return memo
    }
}

// MARK: - ADD Trade Account
class TransactionMemoAddTradeAccount: ObservableObject, CustomStringConvertible {
    @Published var address: String
    
    init(address: String) {
        self.address = address
    }
    var description: String {
        return toString()
    }
    func toString() -> String {
        "TRADE+:\(self.address)"
    }
}

// MARK: - WITHDRAW Trade Account
class TransactionMemoWithdrawTradeAccount: ObservableObject, CustomStringConvertible {
    @Published var address: String
    
    init(address: String) {
        self.address = address
    }
    var description: String {
        return toString()
    }
    func toString() -> String {
        "TRADE-:\(self.address)"
    }
}

// MARK: - BOND, UNBOND & LEAVE
class TransactionMemoNodeMaintenance: ObservableObject, CustomStringConvertible {
    @Published var nodeAddress: String
    @Published var provider: String?
    @Published var fee: Double?
    @Published var amount: Double?
    @Published var action: NodeAction
    
    enum NodeAction {
        case bond
        case unbond
        case leave
    }
    
    init(nodeAddress: String, provider: String?, fee: Double?, amount: Double?, action: NodeAction) {
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
            memo = "UNBOND:\(self.nodeAddress):\(self.amount ?? 0)"
        case .leave:
            memo = "LEAVE:\(self.nodeAddress)"
        }
        if let provider = self.provider, let fee = self.fee {
            memo += ":\(provider):\(fee)"
        }
        return memo
    }
}

// MARK: - DONATE & RESERVE
class TransactionMemoDonateReserve: ObservableObject, CustomStringConvertible {
    @Published var pool: String?
    
    init(pool: String?) {
        self.pool = pool
    }
    var description: String {
        return toString()
    }
    func toString() -> String {
        guard let pool = self.pool else {
            return "RESERVE"
        }
        return "DONATE:\(pool)"
    }
}

// MARK: - MIGRATE
class TransactionMemoMigrate: ObservableObject, CustomStringConvertible {
    @Published var blockHeight: Int
    
    init(blockHeight: Int) {
        self.blockHeight = blockHeight
    }
    var description: String {
        return toString()
    }
    func toString() -> String {
        "MIGRATE:\(self.blockHeight)"
    }
}

// MARK: - NOOP
class NoOp: ObservableObject {
}
