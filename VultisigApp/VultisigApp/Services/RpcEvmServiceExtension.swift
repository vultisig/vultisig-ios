import Foundation
import BigInt

extension RpcEvmService {
    
    // Method to fetch the fastest gas fee
    func getFastestGasFee() async throws -> (maxFeePerGas: BigInt, maxPriorityFeePerGas: BigInt) {
        let historicalBlocks = 4
        let percentiles = [25, 50, 99]
        
        // Fetch fee history
        let feeHistory = try await fetchFeeHistory(blockCount: historicalBlocks, percentiles: percentiles)
        
        // Format the fee history data
        let formattedHistory = try formatFeeHistory(feeHistory)
        
        // Calculate the slow, average, and fast gas fees
        let slowPriorityFee = try calculatePriorityFee(formattedHistory: formattedHistory, percentileIndex: 0)
        let averagePriorityFee = try calculatePriorityFee(formattedHistory: formattedHistory, percentileIndex: 1)
        let fastPriorityFee = try calculatePriorityFee(formattedHistory: formattedHistory, percentileIndex: 2)
        
        print("Slow Priority Fee Per Gas (1st percentile): \(slowPriorityFee)")
        print("Average Priority Fee Per Gas (50th percentile): \(averagePriorityFee)")
        print("Fast Priority Fee Per Gas (99th percentile): \(fastPriorityFee)")
        
        // Fetch base fee from the pending block
        let pendingBlock = try await fetchPendingBlock()
        guard let baseFeePerGasHex = pendingBlock["baseFeePerGas"] as? String else {
            throw RpcEvmServiceError.rpcError(code: -1, message: "Failed to get base fee per gas")
        }
        let baseFeePerGas = BigInt(baseFeePerGasHex.stripHexPrefix(), radix: 16) ?? BigInt(0)
        
        let slowFee = baseFeePerGas + slowPriorityFee
        let averageFee = baseFeePerGas + averagePriorityFee
        let fastFee = baseFeePerGas + fastPriorityFee
        
        print("Gas Fee Estimates: { slow: \(slowFee), average: \(averageFee), fast: \(fastFee) }")
        
        let maxFeePerGas = baseFeePerGas + fastPriorityFee
        
        return (maxFeePerGas, fastPriorityFee)
    }
    
    // Fetch fee history
    private func fetchFeeHistory(blockCount: Int, percentiles: [Int]) async throws -> [String: Any] {
        return try await sendRPCRequest(method: "eth_feeHistory", params: [blockCount, "pending", percentiles]) { result in
            guard let feeHistory = result as? [String: Any] else {
                throw RpcEvmServiceError.rpcError(code: -1, message: "Invalid fee history format")
            }
            return feeHistory
        }
    }
    
    // Fetch pending block
    private func fetchPendingBlock() async throws -> [String: Any] {
        return try await sendRPCRequest(method: "eth_getBlockByNumber", params: ["pending", false]) { result in
            guard let block = result as? [String: Any] else {
                throw RpcEvmServiceError.rpcError(code: -1, message: "Invalid block format")
            }
            return block
        }
    }
    
    // Helper method to format the fee history data
    private func formatFeeHistory(_ result: [String: Any]) throws -> [[String: Any]] {
        guard let oldestBlock = result["oldestBlock"] as? String,
              let baseFeePerGas = result["baseFeePerGas"] as? [String],
              let gasUsedRatio = result["gasUsedRatio"] as? [Double],
              let reward = result["reward"] as? [[String]] else {
            throw RpcEvmServiceError.rpcError(code: -1, message: "Invalid fee history format")
        }
        
        // Ensure the lengths of the arrays match
        let minCount = min(baseFeePerGas.count, gasUsedRatio.count, reward.count)
        
        var formattedBlocks = [[String: Any]]()
        for i in 0..<minCount {
            let block = [
                "number": BigInt(oldestBlock.stripHexPrefix(), radix: 16)! + BigInt(i),
                "baseFeePerGas": BigInt(baseFeePerGas[i].stripHexPrefix(), radix: 16) ?? BigInt(0),
                "gasUsedRatio": gasUsedRatio[i],
                "priorityFeePerGas": reward[i].map { BigInt($0.stripHexPrefix(), radix: 16) ?? BigInt(0) }
            ] as [String : Any]
            formattedBlocks.append(block)
        }
        return formattedBlocks
    }
    
    // Helper method to calculate priority fee based on the specified percentile
    private func calculatePriorityFee(formattedHistory: [[String: Any]], percentileIndex: Int) throws -> BigInt {
        var priorityFees = [BigInt]()
        for block in formattedHistory {
            guard let priorityFeePerGas = block["priorityFeePerGas"] as? [BigInt] else {
                throw RpcEvmServiceError.rpcError(code: -1, message: "Invalid priority fee format")
            }
            priorityFees.append(priorityFeePerGas[percentileIndex])
        }
        let total = priorityFees.reduce(BigInt(0), +)
        return total / BigInt(priorityFees.count)
    }
}
