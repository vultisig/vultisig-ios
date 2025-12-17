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
    
    @StateObject private var model = CircleViewModel()
    @State private var hasCheckedBackend = false
    
    var content: some View {
        ZStack {
            Theme.colors.bgPrimary.ignoresSafeArea()
            
            if !hasCheckedBackend {
                // Mostrar loading enquanto verifica backend
                ProgressView()
                    .progressViewStyle(.circular)
            } else if model.missingEth {
                // Mostrar aviso para adicionar ETH
                VStack(spacing: 24) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.orange)
                    
                    Text("Ethereum Required")
                        .font(.title2)
                        .bold()
                        .foregroundStyle(Theme.colors.textPrimary)
                    
                    Text("Please add Ethereum to your vault to use Circle.")
                        .font(.body)
                        .foregroundStyle(Theme.colors.textLight)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                VStack {
                    if let address = vault.circleWalletAddress, !address.isEmpty {
                        CircleDashboardView(vault: vault, model: model)
                    } else {
                        CircleSetupView(vault: vault, model: model)
                    }
                }
            }
        }
        .onAppear {
            print("[Circle] onAppear - Local address: \(vault.circleWalletAddress ?? "nil")")
            Task { await checkExistingWallet() }
        }
        .navigationTitle(NSLocalizedString("circleTitle", comment: "Circle"))
        .navigationDestination(isPresented: $model.showDeposit) {
            CircleDepositView(vault: vault)
        }
        .navigationDestination(isPresented: $model.showWithdraw) {
            CircleWithdrawView(vault: vault, model: model)
        }
    }
    
    private func checkExistingWallet() async {
        print("[Circle] checkExistingWallet START")
        await MainActor.run { model.isLoading = true }
        
        do {
            print("[Circle] Calling API...")
            let existingAddress = try await model.logic.checkExistingWallet(vault: vault)
            print("[Circle] API returned: \(existingAddress ?? "nil")")
            await MainActor.run {
                if let existingAddress, !existingAddress.isEmpty {
                    print("[Circle] Updating vault address from '\(vault.circleWalletAddress ?? "nil")' to '\(existingAddress)'")
                    vault.circleWalletAddress = existingAddress
                } else {
                    print("[Circle] API returned nil/empty - keeping local: \(vault.circleWalletAddress ?? "nil")")
                }
                model.isLoading = false
                hasCheckedBackend = true
                print("[Circle] checkExistingWallet DONE - Final address: \(vault.circleWalletAddress ?? "nil")")
            }
        } catch let error as CircleServiceError {
            print("[Circle] CircleServiceError: \(error)")
            await MainActor.run {
                if case .keysignError(let msg) = error, msg.contains("No Ethereum") || msg.contains("No ETH") {
                    model.missingEth = true
                }
                model.isLoading = false
                hasCheckedBackend = true
            }
        } catch {
            print("[Circle] API ERROR: \(error)")
            await MainActor.run {
                model.isLoading = false
                hasCheckedBackend = true
            }
        }
    }
}

// MARK: - View Model (State Only)
final class CircleViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: Error?
    @Published var missingEth = false
    @Published var balance: Decimal = .zero
    @Published var ethBalance: Decimal = .zero
    @Published var apy: String = "0%"
    @Published var totalRewards: String = "0"
    @Published var currentRewards: String = "0"
    
    @Published var showDeposit = false
    @Published var showWithdraw = false
    
    let logic = CircleViewLogic()
}

// MARK: - Logic (Methods)
struct CircleViewLogic {
    
    struct CircleWithdrawalInfo {
        let usdcContract: String
    }
    
    func checkExistingWallet(vault: Vault) async throws -> String? {
        let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
        let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
        
        guard let ethCoin = vault.coins.first(where: { $0.chain == chain }) else {
            print("[Circle] ERROR: No ETH coin found in vault!")
            throw CircleServiceError.keysignError("No Ethereum found in vault. Please add Ethereum first.")
        }
        
        return try await CircleApiService.shared.fetchWallet(ethAddress: ethCoin.address)
    }

    func createWallet(vault: Vault, force: Bool = false) async throws -> String {
        let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
        let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
        
        guard let ethCoin = vault.coins.first(where: { $0.chain == chain }) else {
            throw CircleServiceError.keysignError("No ETH coin found in vault. Please add Ethereum first.")
        }
        
        return try await CircleApiService.shared.createWallet(ethAddress: ethCoin.address, force: force)
    }
    
    /// Returns: (USDC Balance, ETH Balance, Yield Response)
    func fetchData(address: String, vault: Vault) async throws -> (Decimal, Decimal, CircleApiService.CircleYieldResponse) {
        let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
        let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
        
        let usdcContract = isSepolia ? CircleConstants.usdcSepolia : CircleConstants.usdcMainnet
        
        do {
            let service = try EvmService.getService(forChain: chain)
            
            guard let nativeCoin = vault.coins.first(where: { $0.chain == chain && $0.isNativeToken }) else {
                return (.zero, .zero, CircleApiService.CircleYieldResponse(apy: "", totalRewards: "", currentRewards: ""))
            }
            
            async let usdcBalanceBigInt = service.fetchERC20TokenBalance(contractAddress: usdcContract, walletAddress: address)
            async let ethBalanceString = service.getBalance(coin: nativeCoin.toCoinMeta(), address: address)
            
            let (usdcVal, ethValStr) = try await (usdcBalanceBigInt, ethBalanceString)
            let ethVal = BigInt(ethValStr) ?? 0
            
            let usdcBalance = (Decimal(string: String(usdcVal)) ?? 0) / pow(10, 6)
            let ethBalance = (Decimal(string: String(ethVal)) ?? 0) / pow(10, 18)
            
            let yield = CircleApiService.CircleYieldResponse(apy: "", totalRewards: "", currentRewards: "")
            
            return (usdcBalance, ethBalance, yield)
            
        } catch {
            return (.zero, .zero, CircleApiService.CircleYieldResponse(apy: "", totalRewards: "", currentRewards: ""))
        }
    }

    func getWithdrawalPayload(vault: Vault, recipient: String, amount: BigInt, isNative: Bool = false) async throws -> KeysignPayload {
        guard let circleWalletAddress = vault.circleWalletAddress else {
            throw CircleServiceError.keysignError("Missing Circle Wallet Address")
        }
        
        let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
        let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
        
        let usdcContract = isSepolia ? CircleConstants.usdcSepolia : CircleConstants.usdcMainnet
        
        let withdrawalInfo = CircleWithdrawalInfo(usdcContract: usdcContract)
        
        let (to, value, data) = try await CircleService.shared.getWithdrawalValues(
            vault: vault,
            recipientAddress: recipient,
            amount: amount,
            info: withdrawalInfo,
            isNative: isNative
        )
        
        let service = try EvmService.getService(forChain: chain)
        
        let senderAddress = vault.coins.first(where: { $0.chain == chain })?.address ?? ""
        if senderAddress.isEmpty {
            throw CircleServiceError.keysignError("Missing ETH Address for \(chain.name)")
        }
        
        // Use FAST fee mode for Circle withdrawals
        let (gasPrice, priorityFee, nonce) = try await service.getGasInfo(fromAddress: senderAddress, mode: .fast)
        
        // Apply boost for faster confirmation
        let minMaxFee = BigInt(2_000_000_000) // 2 Gwei minimum
        let boostedGasPrice = max(gasPrice * 2, minMaxFee)
        
        // Priority fee must be <= max fee
        let desiredPriorityFee = max(priorityFee * 2, BigInt(100_000_000)) // At least 0.1 Gwei
        let boostedPriorityFee = min(desiredPriorityFee, boostedGasPrice)
        
        var dataHex = data.hexString
        if !dataHex.hasPrefix("0x") {
            dataHex = "0x" + dataHex
        }
        
        // Verify Circle Wallet is deployed
        let code = try await service.getCode(address: to)
        let isDeployed = code != "0x" && code.count > 2
        
        if !isDeployed {
            throw CircleServiceError.walletNotDeployed
        }
        
        // Estimate Gas
        let gasLimit = try await service.estimateGasLimitForSwap(
            senderAddress: senderAddress,
            toAddress: to,
            value: value,
            data: dataHex
        )
        
        guard let coin = vault.coins.first(where: { $0.chain == chain && $0.isNativeToken }) else {
            throw CircleServiceError.keysignError("Missing ETH Coin")
        }
        
        let chainSpecific = BlockChainSpecific.Ethereum(
            maxFeePerGasWei: boostedGasPrice,
            priorityFeeWei: boostedPriorityFee,
            nonce: nonce,
            gasLimit: gasLimit
        )
        
        let gasLimitInt64 = Int64(gasLimit.description) ?? 200000
        
        let executeQuote = EVMQuote(
            dstAmount: "0",
            tx: EVMQuote.Transaction(
                from: senderAddress,
                to: to,
                data: dataHex,
                value: "0",
                gasPrice: boostedGasPrice.description, 
                gas: gasLimitInt64
            )
        )
        
        let genericPayload = GenericSwapPayload(
            fromCoin: coin,
            toCoin: coin,
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
