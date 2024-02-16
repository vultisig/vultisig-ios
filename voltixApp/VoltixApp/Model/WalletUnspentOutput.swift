import Foundation

// Root structure for the JSON response
struct WalletUnspentOutput: Codable {
    
    var balanceInBTC: String {
        return formatAsBitcoin(balance)
    }
    
    var finalBalanceInBTC: String {
        return formatAsBitcoin(finalBalance)
    }
    
    // Helper function to format an amount in satoshis as Bitcoin
    private func formatAsBitcoin(_ satoshis: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8 // Bitcoin can have up to 8 decimal places
        formatter.minimumFractionDigits = 1 // Show at least one decimal to indicate it's a decimal value
        formatter.decimalSeparator = "." // Use dot as the decimal separator
        
        // Optionally, set the locale to "en_US_POSIX" for a more standardized formatting
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        let btcValue = Double(satoshis) / 100_000_000.0 // Convert satoshis to BTC
        return formatter.string(from: NSNumber(value: btcValue)) ?? "0.0"
    }
    
    func balanceInUSD(usdPrice: Double?) -> String? {
        guard let usdPrice = usdPrice else { return nil }
        let balanceBTC = Double(self.balance) / 100_000_000.0 // Convert satoshis to BTC
        let balanceUSD = balanceBTC * usdPrice // Convert BTC to USD
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current // Adjust this as needed
        // Optional: Customize the formatter further if needed
        formatter.currencyCode = "USD" // Uncomment if you want to force USD formatting
        
        return formatter.string(from: NSNumber(value: balanceUSD))
    }
    
    
    let address: String
    let totalReceived: Int
    let totalSent: Int
    let balance: Int
    let unconfirmedBalance: Int
    let finalBalance: Int
    let nTx: Int
    let unconfirmedNTx: Int
    let finalNTx: Int
    let txrefs: [TransactionRef]?
    let txUrl: String
    
    enum CodingKeys: String, CodingKey {
        case address
        case totalReceived = "total_received"
        case totalSent = "total_sent"
        case balance
        case unconfirmedBalance = "unconfirmed_balance"
        case finalBalance = "final_balance"
        case nTx = "n_tx"
        case unconfirmedNTx = "unconfirmed_n_tx"
        case finalNTx = "final_n_tx"
        case txrefs
        case txUrl = "tx_url"
    }
}

struct TransactionRef: Codable {
    let txHash: String?
    let blockHeight: Int?
    let txInputN: Int?
    let txOutputN: Int?
    let value: Int?
    let refBalance: Int?
    let spent: Bool?
    let confirmations: Int?
    let confirmed: String?
    let doubleSpend: Bool?
    
    enum CodingKeys: String, CodingKey {
        case txHash = "tx_hash"
        case blockHeight = "block_height"
        case txInputN = "tx_input_n"
        case txOutputN = "tx_output_n"
        case value
        case refBalance = "ref_balance"
        case spent
        case confirmations
        case confirmed
        case doubleSpend = "double_spend"
    }
}
