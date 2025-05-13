import XCTest
import BigInt
import WalletCore
@testable import VultisigApp

@MainActor
class SendCryptoViewModelTests: XCTestCase {
    var sut: SendCryptoViewModel!
    let placeholderHexPublicKey = "0xplaceholderPublicKey"
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        sut = SendCryptoViewModel()
    }
    
    override func tearDownWithError() throws {
        sut = nil
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
        
        sut.setMaxValues(tx: tx, percentage: 100)
        
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
        XCTAssertFalse(sut.isLoading, "isLoading should be false after operation")
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
