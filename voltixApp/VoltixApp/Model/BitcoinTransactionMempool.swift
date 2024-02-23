import Foundation

class BitcoinTransactionMempool: Codable {
    let txid: String
    let version: Int
    let locktime: Int
    let vin: [Input]
    let vout: [Output]
    let fee: Int
    let status: TransactionStatus
    private var _userAddress: String?
    
    var userAddress: String {
        get { _userAddress ?? "" }
        set { _userAddress = newValue }
    }
    
    init(txid: String, version: Int, locktime: Int, vin: [Input], vout: [Output], fee: Int, status: TransactionStatus, userAddress: String) {
        self.txid = txid
        self.version = version
        self.locktime = locktime
        self.vin = vin
        self.vout = vout
        self.fee = fee
        self.status = status
        self.userAddress = userAddress
    }
    
    var isSent: Bool {
        return vin.contains { input in
            input.prevout?.scriptpubkey_address == userAddress
        }
    }
    
    var isReceived: Bool {
        return vout.contains { output in
            output.scriptpubkey_address == userAddress
        }
    }
    
    var sentTo: [String] {
        guard isSent else { return [] }
        return vout.filter { $0.scriptpubkey_address != userAddress }.map { $0.scriptpubkey_address }
    }
    
    var receivedFrom: [String] {
        guard isReceived else { return [] }
        return vin.compactMap { $0.prevout?.scriptpubkey_address }
    }
    
    var amountReceived: Int {
        guard isReceived else { return 0 }
        return vout.reduce(0) { $0 + ($1.scriptpubkey_address == userAddress ? $1.value : 0) }
    }
    
    var amountSent: Int {
        guard isSent else { return 0 }
        let totalSentToOthers = vout.reduce(0) { $0 + ($1.scriptpubkey_address != userAddress ? $1.value : 0) }
        return totalSentToOthers
    }
    
    class Input: Codable {
        let txid: String
        let vout: Int
        let prevout: PreviousOutput?
        let sequence: UInt32
        let scriptsig: String?
        let scriptsig_asm: String?
        let witness: [String]?
        let is_coinbase: Bool?
        
        class PreviousOutput: Codable {
            let scriptpubkey: String
            let scriptpubkey_asm: String
            let scriptpubkey_type: String
            let scriptpubkey_address: String
            let value: Int
        }
    }
    
    class Output: Codable {
        let scriptpubkey: String
        let scriptpubkey_asm: String
        let scriptpubkey_type: String
        let scriptpubkey_address: String
        let value: Int
    }
    
    class TransactionStatus: Codable {
        let confirmed: Bool
        let block_height: Int?
        let block_hash: String?
        let block_time: Int?
    }
}

    // Trying to get the MEMO
extension BitcoinTransactionMempool {
    var opReturnData: String? {
        for output in vout {
                // Assuming scriptpubkey_asm is a non-optional String
            let asm = output.scriptpubkey_asm
            if asm.hasPrefix("OP_RETURN") {
                    // Extract the data part after "OP_RETURN"
                let components = asm.components(separatedBy: " ")
                if components.count > 1 {
                        // The actual data starts after "OP_RETURN" and is usually hex-encoded
                    let dataHex = components.dropFirst().joined(separator: " ")
                        // Since dataHex is derived from a non-optional String, no need for optional binding here
                    return dataHex
                }
            }
        }
        return nil
    }
}


