import Foundation

class UTXOTransactionMempool: Codable {
    let txid: String
    let version: Int
    let locktime: Int
    let vin: [UTXOTransactionMempoolInput]
    let vout: [UTXOTransactionMempoolOutput]
    let fee: Int
    let status: UTXOTransactionStatus
    private var _userAddress: String?

    var userAddress: String {
        get { _userAddress ?? "" }
        set { _userAddress = newValue }
    }

    var isSent: Bool {
        vin.contains { input in
            input.prevout?.scriptpubkey_address == userAddress
        }
    }

    var isReceived: Bool {
        vout.contains { output in
            output.scriptpubkey_address == userAddress
        }
    }

    var sentTo: [String] {
        guard isSent else { return [] }
        return vout.compactMap { output in
            guard let address = output.scriptpubkey_address, address != userAddress else { return nil }
            return address
        }
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

    init(txid: String, version: Int, locktime: Int, vin: [UTXOTransactionMempoolInput], vout: [UTXOTransactionMempoolOutput], fee: Int, status: UTXOTransactionStatus, userAddress: String) {
        self.txid = txid
        self.version = version
        self.locktime = locktime
        self.vin = vin
        self.vout = vout
        self.fee = fee
        self.status = status
        self.userAddress = userAddress
    }
}
