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
    
    func testSetMaxValues_Bitcoin_100Percent() async throws {
        guard let currentVault = ApplicationState.shared.currentVault else {
            XCTFail("Current vault is nil. Please ensure a vault is loaded.")
            return
        }
        
        print("TEST Current VAULT Name: \(currentVault.name)")
        guard let coin = currentVault.coins.first(where: { $0.chain == .bitcoin && $0.isNativeToken }) else {
            XCTFail("No native BTC coin found in the current vault. Coins available: \(currentVault.coins.map({ "\($0.ticker) (\($0.chain.name))" }))")
            return
        }
        
        print("Found BTC Coin: \(coin.ticker), Address: \(coin.address), RawBalance: \(coin.rawBalance)")
        
        let expectation = XCTestExpectation(description: "SetMaxValues for Bitcoin 100% completes using live service with vault coin")
        
        let btcToAddress = coin.address
        
        let tx = await createTx(coin: coin, toAddress: btcToAddress)
        
        viewModel.setMaxValues(tx: tx, percentage: 100)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            XCTAssertTrue(tx.sendMaxAmount)
            
            print("Teste BTC 100% (Moeda do Vault) - Valor Real: \(tx.amount), Valor Fiat Real: \(tx.amountInFiat)")
            
            if tx.amount.isEmpty {
                XCTFail("tx.amount está vazio.")
            } else {
                
                XCTAssertTrue(tx.amountInRaw.description == coin.rawBalance, "The total amount if 100% in BTC must be equal to the raw balance of the vault BTC coin, because the fees will be deducted from the raw balance directly in the blockchain.")
                
            }
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 15.0) // Aumentado timeout
        XCTAssertFalse(viewModel.isLoading, "isLoading should be false after operation")
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
            XCTAssertTrue(tx.sendMaxAmount)
            
            print("Teste BTC 100% com fee - Valor tx.amount: \(tx.amount), Valor tx.amountInRaw: \(tx.amountInRaw.description), Saldo coin.rawBalance: \(coin.rawBalance)")
            
            if tx.amount.isEmpty {
                XCTFail("tx.amount está vazio.")
            } else {
                // ✅ Aqui você chama seu método de transaction plan para calcular a fee real.
                // Exemplo fictício, substitua por seu método real:
                
                tx.toAddress = "1K6KoYC69NnafWJ7YgtrpwJxBLiijWqwa6"
                
                let plan = self.viewModel.getTransactionPlan(tx: tx)
                
                print("Plan: \(String(describing: plan))")
                
                print("Plan Amount: \(String(describing: plan?.amount))")
                
                print("Plan Available Amount: \(String(describing: plan?.availableAmount))")
                
                print("Plan Fee: \(String(describing: plan?.fee))")
                
                
                let fee = (plan?.fee ?? 0).description.toBigInt()
                
                let expectedAmountInRaw = initialRawBalanceBigInt - fee
                
                XCTAssertEqual(tx.amountInRaw, expectedAmountInRaw,
                               "The amount in raw for 100% BTC should be raw balance minus fee. tx.amountInRaw: \(tx.amountInRaw), expected: \(expectedAmountInRaw), fee: \(fee)")
            }
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 15.0)
        XCTAssertFalse(viewModel.isLoading)
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
        
        let percentages = [25, 50, 75, 100]
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
                print("\n🔍 Testing \(percentage)%")
                print("Initial Raw Balance: \(initialRawBalanceBigInt)")
                
                tx.toAddress = btcToAddress
                let plan = self.viewModel.getTransactionPlan(tx: tx)
                
                let fee = (plan?.fee ?? 0).description.toBigInt() ?? BigInt(0)
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
    
    func testSetMaxValues_Bitcoin_50Percent() async throws {
        guard let currentVault = ApplicationState.shared.currentVault else {
            XCTFail("Current vault is nil. Please ensure a vault is loaded.")
            return
        }
        
        guard let coin = currentVault.coins.first(where: { $0.chain == .bitcoin && $0.isNativeToken }) else {
            XCTFail("No native BTC coin found in the current vault.")
            return
        }
        
        let expectation = XCTestExpectation(description: "SetMaxValues for Bitcoin 50% completes using live service with vault coin")
        
        let btcToAddress = coin.address
        let tx = await createTx(coin: coin, toAddress: btcToAddress)
        
        guard let initialRawBalanceBigInt = BigInt(coin.rawBalance) else {
            XCTFail("Could not convert initial coin.rawBalance to BigInt: \(coin.rawBalance)")
            return
        }
        
        guard initialRawBalanceBigInt > 0 else {
            print("Skipping 50% test as initial raw balance for BTC is zero or invalid.")
            expectation.fulfill()
            await fulfillment(of: [expectation], timeout: 1.0)
            return
        }
        
        viewModel.setMaxValues(tx: tx, percentage: 50)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            XCTAssertFalse(tx.sendMaxAmount)
            
            print("Teste BTC 50% (Moeda do Vault) - Valor tx.amount: \(tx.amount), Valor tx.amountInRaw: \(tx.amountInRaw.description), Saldo coin.rawBalance Inicial: \(coin.rawBalance)")
            
            if tx.amount.isEmpty {
                XCTFail("tx.amount está vazio para 50%.")
            } else {
                let expectedAmountInRaw = initialRawBalanceBigInt / 2
                XCTAssertEqual(tx.amountInRaw, expectedAmountInRaw, "The amount in raw for 50% BTC should be approximately half of the coin's initial raw balance. tx.amountInRaw: \(tx.amountInRaw), expected: \(expectedAmountInRaw)")
            }
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 15.0)
        XCTAssertFalse(viewModel.isLoading)
    }
    
    func testSetMaxValues_Bitcoin_75Percent() async throws {
        guard let currentVault = ApplicationState.shared.currentVault else {
            XCTFail("Current vault is nil. Please ensure a vault is loaded.")
            return
        }
        
        guard let coin = currentVault.coins.first(where: { $0.chain == .bitcoin && $0.isNativeToken }) else {
            XCTFail("No native BTC coin found in the current vault.")
            return
        }
        
        let expectation = XCTestExpectation(description: "SetMaxValues for Bitcoin 75% completes using live service with vault coin")
        
        let btcToAddress = coin.address
        let tx = await createTx(coin: coin, toAddress: btcToAddress)
        
        guard let initialRawBalanceBigInt = BigInt(coin.rawBalance) else {
            XCTFail("Could not convert initial coin.rawBalance to BigInt: \(coin.rawBalance)")
            return
        }
        
        guard initialRawBalanceBigInt > 0 else {
            print("Skipping 75% test as initial raw balance for BTC is zero or invalid.")
            expectation.fulfill()
            await fulfillment(of: [expectation], timeout: 1.0)
            return
        }
        
        viewModel.setMaxValues(tx: tx, percentage: 75)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            XCTAssertFalse(tx.sendMaxAmount)
            
            print("Teste BTC 75% (Moeda do Vault) - Valor tx.amount: \(tx.amount), Valor tx.amountInRaw: \(tx.amountInRaw.description), Saldo coin.rawBalance Inicial: \(coin.rawBalance)")
            
            if tx.amount.isEmpty {
                XCTFail("tx.amount está vazio para 75%.")
            } else {
                let initialRawBalanceDecimal = Decimal(string: initialRawBalanceBigInt.description) ?? .zero
                let calculatedAmount = (initialRawBalanceDecimal * 75) / 100
                let expectedAmountInRawDecimal = calculatedAmount.rounded(scale: 0, roundingMode: .up)
                
                guard let expectedAmountInRaw = BigInt(expectedAmountInRawDecimal.description) else {
                    XCTFail("Failed to convert expectedAmountInRawDecimal to BigInt.")
                    return
                }
                
                XCTAssertEqual(tx.amountInRaw, expectedAmountInRaw,
                               "The amount in raw for 75% BTC should be approximately 75% of the coin's initial raw balance. tx.amountInRaw: \(tx.amountInRaw), expected: \(expectedAmountInRaw)")
            }
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 15.0)
        XCTAssertFalse(viewModel.isLoading)
    }
    
    func testSetMaxValues_Bitcoin_25Percent() async throws {
        guard let currentVault = ApplicationState.shared.currentVault else {
            XCTFail("Current vault is nil. Please ensure a vault is loaded.")
            return
        }
        
        guard let coin = currentVault.coins.first(where: { $0.chain == .bitcoin && $0.isNativeToken }) else {
            XCTFail("No native BTC coin found in the current vault.")
            return
        }
        
        let expectation = XCTestExpectation(description: "SetMaxValues for Bitcoin 25% completes using live service with vault coin")
        
        let btcToAddress = coin.address
        let tx = await createTx(coin: coin, toAddress: btcToAddress)
        
        guard let initialRawBalanceBigInt = BigInt(coin.rawBalance) else {
            XCTFail("Could not convert initial coin.rawBalance to BigInt: \(coin.rawBalance)")
            return
        }
        
        guard initialRawBalanceBigInt > 0 else {
            print("Skipping 25% test as initial raw balance for BTC is zero or invalid.")
            expectation.fulfill()
            await fulfillment(of: [expectation], timeout: 1.0)
            return
        }
        
        viewModel.setMaxValues(tx: tx, percentage: 25)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            XCTAssertFalse(tx.sendMaxAmount)
            
            print("Teste BTC 25% (Moeda do Vault) - Valor tx.amount: \(tx.amount), Valor tx.amountInRaw: \(tx.amountInRaw.description), Saldo coin.rawBalance Inicial: \(coin.rawBalance)")
            
            if tx.amount.isEmpty {
                XCTFail("tx.amount está vazio para 25%.")
            } else {
                let expectedAmountInRaw = (initialRawBalanceBigInt * 25) / 100
                XCTAssertEqual(tx.amountInRaw, expectedAmountInRaw, "The amount in raw for 25% BTC should be approximately 25% of the coin's initial raw balance. tx.amountInRaw: \(tx.amountInRaw), expected: \(expectedAmountInRaw)")
            }
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 15.0)
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
}
extension Decimal {
    func rounded(scale: Int = 0, roundingMode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var result = Decimal()
        var value = self
        NSDecimalRound(&result, &value, scale, roundingMode)
        return result
    }
}
