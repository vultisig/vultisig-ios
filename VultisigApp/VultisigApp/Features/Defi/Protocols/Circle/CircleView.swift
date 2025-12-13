//
//  CircleView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-11.
//

import SwiftUI
import SwiftData
import BigInt
import WalletCore
import VultisigCommonData

struct CircleView: View {
    let vault: Vault
    
    // Logic/State separation as requested
    @StateObject private var model = CircleViewModel()
    
    var body: some View {
        ZStack {
            Theme.colors.bgPrimary.ignoresSafeArea()
            
            VStack {
                if let address = vault.circleWalletAddress, !address.isEmpty {
                    CircleDashboardView(vault: vault, model: model)
                } else {
                    CircleSetupView(vault: vault, model: model)
                }
            }
        }
        .navigationTitle(NSLocalizedString("circleTitle", comment: "Circle"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - View Model (State Only)
final class CircleViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: Error?
    @Published var balance: Decimal = .zero
    @Published var ethBalance: Decimal = .zero
    @Published var apy: String = "0%"
    @Published var totalRewards: String = "0"
    @Published var currentRewards: String = "0"
    
    // Logic is delegated to CircleViewLogic struct
    let logic = CircleViewLogic()
}

// MARK: - Logic (Methods)
struct CircleViewLogic {
    func createWallet(vault: Vault) async throws -> String {
        print("CircleViewLogic: createWallet called for vault pubKey: \(vault.pubKeyECDSA)")
        return try await CircleApiService.shared.createWallet(vaultPubkey: vault.pubKeyECDSA)
    }
    
    // Returns: (USDC Balance, ETH Balance, Yield Response)
    func fetchData(address: String, vault: Vault) async throws -> (Decimal, Decimal, CircleApiService.CircleYieldResponse) {
        print("CircleViewLogic: fetchData called for address: \(address)")
        
        // 1. Determine Chain and USDC Contract
        // Check if vault has Sepolia enabled
        let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
        let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
        
        // USDC Constants
        let usdcMainnet = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
        let usdcSepolia = "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238" 
        let usdcContract = isSepolia ? usdcSepolia : usdcMainnet
        
        print("CircleViewLogic: Using chain \(chain.name), USDC Contract: \(usdcContract)")
        
        do {
            let service = try EvmService.getService(forChain: chain)
            
            // Find Native Coin for Context (needed for RPC calls sometimes)
            // Even if we query a different address, we need a CoinMeta to specify the chain asset details
            guard let nativeCoin = vault.coins.first(where: { $0.chain == chain && $0.isNativeToken }) else {
                 print("CircleViewLogic: No native coin found for chain \(chain)")
                 return (.zero, .zero, CircleApiService.CircleYieldResponse(apy: "0", totalRewards: "0", currentRewards: "0"))
            }
            
            // Fetch USDC Balance
            async let usdcBalanceBigInt = service.fetchERC20TokenBalance(contractAddress: usdcContract, walletAddress: address)
            // Fetch ETH Balance (Native) - returns String (wei)
            async let ethBalanceString = service.getBalance(coin: nativeCoin.toCoinMeta(), address: address)
            
            let (usdcVal, ethValStr) = try await (usdcBalanceBigInt, ethBalanceString)
            let ethVal = BigInt(ethValStr) ?? 0
            
            // USDC is 6 decimals
            let usdcDecimals = 6
            let usdcDivisor = pow(10, usdcDecimals)
            let usdcBalance = (Decimal(string: String(usdcVal)) ?? 0) / usdcDivisor
            
            // ETH is 18 decimals
            let ethDecimals = 18
            let ethDivisor = pow(10, ethDecimals)
            let ethBalance = (Decimal(string: String(ethVal)) ?? 0) / ethDivisor
            
            print("CircleViewLogic: Fetched USDC: \(usdcBalance), ETH: \(ethBalance)")
            
            // Yield is still stubbed as it's not on-chain standard
            // Mocking currentRewards for UI as requested by user (should be API in real implementation)
            let yield = CircleApiService.CircleYieldResponse(apy: "5.17%", totalRewards: "1,293.23", currentRewards: "428.25")
            
            return (usdcBalance, ethBalance, yield)
            
        } catch {
            print("CircleViewLogic: Failed to fetch balance. Error: \(error)")
            // For UI stability, returning 0 with error log is often better for "view" logic.
            return (.zero, .zero, CircleApiService.CircleYieldResponse(apy: "0", totalRewards: "0", currentRewards: "0"))
        }
    }
    
    struct CircleWithdrawalInfo {
        let usdcContract: String
    }

    func getWithdrawalPayload(vault: Vault, recipient: String, amount: BigInt) async throws -> KeysignPayload {
        print("CircleViewLogic: getWithdrawalPayload called. Address: \(vault.circleWalletAddress ?? "nil"), Recipient: \(recipient), Amount: \(amount)")
        
        guard let circleWalletAddress = vault.circleWalletAddress else {
            throw CircleServiceError.keysignError("Missing Circle Wallet Address")
        }
        
        // 1. Determine Chain and Contracts
        let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
        let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
        
        let usdcMainnet = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
        let usdcSepolia = "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"
        let usdcContract = isSepolia ? usdcSepolia : usdcMainnet
        
        let withdrawalInfo = CircleWithdrawalInfo(usdcContract: usdcContract)
        
        // 2. Build Execution Data (CircleService)
        let (to, value, data) = try await CircleService.shared.getWithdrawalValues(
            vault: vault,
            recipientAddress: recipient,
            amount: amount,
            info: withdrawalInfo
        )
        
        // 3. Fetch Gas Info (EvmService)
        let service = try EvmService.getService(forChain: chain)
        
        // The sender is the Vault's ETH address.
        let senderAddress = vault.coins.first(where: { $0.chain == .ethereum })?.address ?? ""
        if senderAddress.isEmpty { throw CircleServiceError.keysignError("Missing ETH Address") }
        
        let (gasPrice, priorityFee, nonce) = try await service.getGasInfo(fromAddress: senderAddress, mode: .normal)
        
        // Estimate Gas
        let gasLimit = try await service.estimateGasLimitForSwap(
            senderAddress: senderAddress,
            toAddress: to,
            value: value,
            data: data.hexString
        )
        
        print("CircleViewLogic: Gas Estimated: \(gasLimit), Nonce: \(nonce)")
        
        // 4. Construct Keysign Payload
        guard let coin = vault.coins.first(where: { $0.chain == .ethereum && $0.isNativeToken }) else {
            throw CircleServiceError.keysignError("Missing ETH Coin")
        }
        
        let chainSpecific = BlockChainSpecific.Ethereum(
            maxFeePerGasWei: gasPrice,
            priorityFeeWei: priorityFee,
            nonce: nonce,
            gasLimit: gasLimit
        )
        
        // Use GenericSwapPayload to carry the execution data
        // EVMQuote requires gas as Int64, implying it might not handle > 64 bit gas limits well, but standard tx usually fits.
        // We cast BigInt gasLimit to Int64.
        let gasLimitInt64 = Int64(gasLimit.description) ?? 200000
        
        let executeQuote = EVMQuote(
            dstAmount: "0",
            tx: EVMQuote.Transaction(
                from: senderAddress,
                to: to,
                data: data.hexString,
                value: "0",
                gasPrice: gasPrice.description, 
                gas: gasLimitInt64
            )
        )
        
        let genericPayload = GenericSwapPayload(
            fromCoin: coin,
            toCoin: coin, // Self-transfer essentially, or transfer to contract
            fromAmount: value,
            toAmountDecimal: Decimal(0),
            quote: executeQuote,
            provider: .oneInch 
        )
        
        let payloadWithData = KeysignPayload(
            coin: coin,
            toAddress: to,
            toAmount: value,
            chainSpecific: chainSpecific,
            utxos: [],
            memo: nil,
            swapPayload: SwapPayload.generic(genericPayload),
            approvePayload: nil,
            vaultPubKeyECDSA: vault.pubKeyECDSA,
            vaultLocalPartyID: vault.localPartyID,
            libType: (vault.libType ?? .GG20) == .DKLS ? "dkls" : "gg20",
            wasmExecuteContractPayload: nil,
            skipBroadcast: false
        )
        
        return payloadWithData
    }
}

