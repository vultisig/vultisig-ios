import XCTest
import BigInt
import WalletCore
@testable import VultisigApp

@MainActor
class SendCryptoViewModelTests: XCTestCase {
    var viewModel: SendCryptoViewModel!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        viewModel = SendCryptoViewModel()
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        try super.tearDownWithError()
    }
    
    func createTx(coin: Coin, toAddress: String = "") async -> SendTransaction {
        let tx = SendTransaction(coin: coin)
        tx.toAddress = toAddress
        await BalanceService.shared.updateBalance(for: coin)
        return tx
    }
    
    func testSetMaxValues_Bitcoin_100Percent_WithFee() async throws {
        guard let currentVault = ApplicationState.shared.currentVault else {
            XCTFail("Current vault is nil. Please ensure a vault is loaded.")
            return
        }
        
        guard let coin = currentVault.coins.first(where: { $0.chain == .bitcoin && $0.isNativeToken }) else {
            XCTFail("No native BTC coin found in the current vault.")
            return
        }
        
        let expectation = XCTestExpectation(description: "SetMaxValues for Bitcoin 100% with fee completes using live service with vault coin")
        
        let btcToAddress = coin.address
        let tx = await createTx(coin: coin, toAddress: btcToAddress)
        
        guard let initialRawBalanceBigInt = BigInt(coin.rawBalance) else {
            XCTFail("Could not convert initial coin.rawBalance to BigInt: \(coin.rawBalance)")
            return
        }
        
        viewModel.setMaxValues(tx: tx, percentage: 100)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            XCTAssertTrue(tx.sendMaxAmount, "Transaction should be marked as sendMax for 100%.")
            
            if tx.amount.isEmpty {
                XCTFail("tx.amount está vazio.")
                expectation.fulfill()
                return
            }
            
            tx.toAddress = btcToAddress
            guard let plan = self.viewModel.getTransactionPlan(tx: tx) else {
                XCTFail("Transaction plan could not be generated.")
                expectation.fulfill()
                return
            }
            
            let fee = (plan.fee).description.toBigInt()
            
            print("""
                Plan Details:
                - Plan Amount: \(plan.amount)
                - Plan Available Amount: \(plan.availableAmount)
                - Plan Fee: \(plan.fee) (as BigInt: \(fee))
                - Initial Raw Balance: \(initialRawBalanceBigInt)
                - tx.amountInRaw: \(tx.amountInRaw)
            """)
            
            // Ensure that amountInRaw is exactly equal to the total balance
            XCTAssertEqual(
                tx.amountInRaw,
                initialRawBalanceBigInt,
                """
                For 100% send, amountInRaw must equal total balance.
                Found: \(tx.amountInRaw), Expected: \(initialRawBalanceBigInt)
                """
            )
            
            // Ensure the fee is deducted on-chain and doesn't affect amountInRaw directly
            let remainingBalanceAfterSend = initialRawBalanceBigInt - tx.amountInRaw
            if remainingBalanceAfterSend < fee {
                XCTFail("""
                    Insufficient remaining balance to cover the fee after setting max value.
                    Remaining: \(remainingBalanceAfterSend), Fee: \(fee)
                """)
            }
            
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 15.0)
        XCTAssertFalse(viewModel.isLoading, "isLoading should be false after operation.")
    }
    
    func testSetMaxValues_Bitcoin_PercentageWithFeeValidation() async throws {
        guard let currentVault = ApplicationState.shared.currentVault else {
            XCTFail("Current vault is nil. Please ensure a vault is loaded.")
            return
        }
        
        guard let coin = currentVault.coins.first(where: { $0.chain == .bitcoin && $0.isNativeToken }) else {
            XCTFail("No native BTC coin found in the current vault.")
            return
        }
        
        let percentages = [25, 50, 75]
        let btcToAddress = "1K6KoYC69NnafWJ7YgtrpwJxBLiijWqwa6"
        
        guard let initialRawBalanceBigInt = BigInt(coin.rawBalance) else {
            XCTFail("Could not convert initial coin.rawBalance to BigInt: \(coin.rawBalance)")
            return
        }
        
        let threshold = BigInt(1) // Tolerance of ±1 satoshi
        
        for percentage in percentages {
            let expectation = XCTestExpectation(description: "Testing \(percentage)% with fee consideration")
            
            let tx = await createTx(coin: coin, toAddress: btcToAddress)
            
            viewModel.setMaxValues(tx: tx, percentage: Double(percentage))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                print("\n Testing \(percentage)%")
                print("Initial Raw Balance: \(initialRawBalanceBigInt)")
                
                tx.toAddress = btcToAddress
                let plan = self.viewModel.getTransactionPlan(tx: tx)
                
                let fee = (plan?.fee ?? 0).description.toBigInt()
                let totalAmount = tx.amountInRaw + fee
                
                print("Fee: \(fee), AmountInRaw: \(tx.amountInRaw), Total: \(totalAmount), Raw Balance: \(initialRawBalanceBigInt)")
                
                if totalAmount > initialRawBalanceBigInt {
                    XCTFail("""
                        Invalid state for \(percentage)%: total amount including fee exceeds available balance.
                        tx.amountInRaw: \(tx.amountInRaw), fee: \(fee), total: \(totalAmount), balance: \(initialRawBalanceBigInt)
                    """)
                } else {
                    let expectedAmountInRaw = (initialRawBalanceBigInt * BigInt(percentage)) / 100
                    
                    let difference = abs(tx.amountInRaw - expectedAmountInRaw)
                    
                    XCTAssertLessThanOrEqual(
                        difference,
                        threshold,
                        """
                        Expected amount for \(percentage)% within threshold ±\(threshold). 
                        tx.amountInRaw: \(tx.amountInRaw), expected: \(expectedAmountInRaw), difference: \(difference), fee: \(fee)
                        """
                    )
                }
                
                expectation.fulfill()
            }
            
            await fulfillment(of: [expectation], timeout: 15.0)
        }
        
        XCTAssertFalse(viewModel.isLoading)
    }
    
}


extension String {
    var isEmptyOrZero: Bool {
        if isEmpty { return true }
        guard let decimalValue = self.toDecimal() else { return true }
        return decimalValue == .zero
    }
    func toDecimal() -> Decimal? {
        return Decimal(string: self)
    }
}

extension BigInt {
    func formatToDecimal(digits: Int) -> String {
        guard let decimalValue = Decimal(string: self.description) else { return "0.0" }
        let divisor = pow(Decimal(10), digits)
        if divisor == .zero { return "0.0" }
        let result = decimalValue / divisor
        return result.formatToDecimal(digits: digits)
    }
}

extension Decimal {
    func formatToDecimal(digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        return formatter.string(from: self as NSDecimalNumber) ?? "\(self)"
    }

    func rounded(scale: Int = 0, roundingMode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var result = Decimal()
        var value = self
        NSDecimalRound(&result, &value, scale, roundingMode)
        return result
    }
}
