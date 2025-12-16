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
    
    // DEBUG: Set to true to always show "Open Account" option
    private let debugMode = true
    @State private var showSetupInDebug = false
    
    var body: some View {
        ZStack {
            Theme.colors.bgPrimary.ignoresSafeArea()
            
            VStack {
                if debugMode && showSetupInDebug {
                    // DEBUG: Force show setup view
                    CircleSetupView(vault: vault, model: model)
                } else if let address = vault.circleWalletAddress, !address.isEmpty {
                    // Has account - show dashboard
                    CircleDashboardView(vault: vault, model: model)
                        .toolbar {
                            if debugMode {
                                ToolbarItem(placement: .primaryAction) {
                                    Menu("🐛 Debug") {
                                        Button("🔄 Recreate Account") {
                                            Task { await recreateWallet() }
                                        }
                                        Button("📝 Show Setup View") {
                                            showSetupInDebug = true
                                        }
                                        Button("🗑️ Clear Account") {
                                            vault.circleWalletAddress = nil
                                        }
                                    }
                                    .foregroundColor(.orange)
                                }
                            }
                        }
                } else {
                    // No account - show setup
                    CircleSetupView(vault: vault, model: model)
                }
            }
        }
        .navigationTitle(NSLocalizedString("circleTitle", comment: "Circle"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: vault.circleWalletAddress) { _ in
            // Reset debug state when address changes
            showSetupInDebug = false
        }
    }
    
    // DEBUG: Recreate wallet and overwrite the address
    private func recreateWallet() async {
        print("🔄 DEBUG: Recreating Circle wallet...")
        print("🔄 DEBUG: Current MSCA address: \(vault.circleWalletAddress ?? "none")")
        
        // Log vault info for debugging
        let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
        let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
        let vaultEthAddress = vault.coins.first(where: { $0.chain == chain })?.address ?? ""
        print("🔄 DEBUG: Vault ETH address: \(vaultEthAddress)")
        
        await MainActor.run { model.isLoading = true }
        
        do {
            // Force create new wallet (will skip checking existing, create fresh)
            let newAddress = try await model.logic.createWallet(vault: vault, force: true)
            
            print("🔄 DEBUG: New MSCA address: \(newAddress)")
            print("🔄 DEBUG: Overwriting vault.circleWalletAddress...")
            
            await MainActor.run {
                vault.circleWalletAddress = newAddress
            }
            
            print("🔄 DEBUG: ✅ Wallet recreated successfully!")
            print("")
            print("🔍 DEBUG: Verifying new MSCA...")
            
            // Wait a moment for blockchain to update
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            
            // Run verification
            await verifyMSCA(mscaAddress: newAddress, expectedOwner: vaultEthAddress, chain: chain)
            
            await MainActor.run {
                model.isLoading = false
            }
            
        } catch {
            print("🔄 DEBUG: ❌ Failed to recreate wallet: \(error)")
            await MainActor.run {
                model.error = error
                model.isLoading = false
            }
        }
    }
    
    // DEBUG: Verify MSCA deployment and owner
    private func verifyMSCA(mscaAddress: String, expectedOwner: String, chain: Chain) async {
        print("╔══════════════════════════════════════════════════════════════════╗")
        print("║              MSCA VERIFICATION REPORT                            ║")
        print("╠══════════════════════════════════════════════════════════════════╣")
        print("║ MSCA Address: \(mscaAddress)")
        print("║ Expected Owner: \(expectedOwner)")
        print("╠══════════════════════════════════════════════════════════════════╣")
        
        do {
            let service = try EvmService.getService(forChain: chain)
            
            // 1. Check if deployed
            print("║ [1/3] Checking deployment...")
            let code = try await service.getCode(address: mscaAddress)
            let isDeployed = code != "0x" && code.count > 2
            print("║       Code length: \(code.count) chars")
            print("║       Is Deployed: \(isDeployed ? "✅ YES" : "❌ NO")")
            
            if !isDeployed {
                print("║")
                print("║ ⚠️  MSCA NOT YET DEPLOYED!")
                print("║ The backend needs to execute transferNativeOwnership")
                print("║ to deploy the MSCA on-chain.")
                print("╚══════════════════════════════════════════════════════════════════╝")
                return
            }
            
            // 2. Fetch owner
            print("║ [2/3] Fetching owner...")
            let owner = await service.fetchContractOwner(contractAddress: mscaAddress)
            print("║       Owner from contract: \(owner ?? "❓ UNKNOWN")")
            
            // 3. Compare
            print("║ [3/3] Comparing owner...")
            if let owner = owner {
                let ownerMatch = owner.lowercased() == expectedOwner.lowercased()
                print("║       Owner matches vault: \(ownerMatch ? "✅ YES" : "❌ NO - MISMATCH!")")
                
                if !ownerMatch {
                    print("║")
                    print("║ ❌ OWNER MISMATCH DETECTED!")
                    print("║    Expected: \(expectedOwner)")
                    print("║    Actual:   \(owner)")
                    print("║")
                    print("║ The backend may still be deriving address incorrectly.")
                }
            } else {
                print("║       Could not fetch owner (contract may not implement owner())")
                print("║       Try checking on Etherscan:")
                print("║       https://etherscan.io/address/\(mscaAddress)#readContract")
            }
            
            // 4. Check USDC balance in new MSCA
            print("║")
            print("║ [BONUS] Checking MSCA balances...")
            let usdcContract = chain == .ethereumSepolia 
                ? "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"
                : "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
            
            let usdcBalance = try await service.fetchERC20TokenBalance(contractAddress: usdcContract, walletAddress: mscaAddress)
            let usdcFormatted = Decimal(string: String(usdcBalance)) ?? 0 / pow(10, 6)
            print("║       USDC Balance: \(usdcFormatted) USDC")
            
            if let nativeCoin = vault.coins.first(where: { $0.chain == chain && $0.isNativeToken }) {
                let ethBalanceStr = try await service.getBalance(coin: nativeCoin.toCoinMeta(), address: mscaAddress)
                let ethBalance = (Decimal(string: ethBalanceStr) ?? 0) / pow(10, 18)
                print("║       ETH Balance: \(ethBalance) ETH")
            }
            
            print("╠══════════════════════════════════════════════════════════════════╣")
            print("║ Etherscan: https://etherscan.io/address/\(mscaAddress)")
            print("╚══════════════════════════════════════════════════════════════════╝")
            
        } catch {
            print("║ ❌ Verification failed: \(error)")
            print("╚══════════════════════════════════════════════════════════════════╝")
        }
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
    
    // MARK: - Diagnostic Report Structure
    struct CircleDiagnosticReport {
        let timestamp: Date
        let chain: Chain
        let chainName: String
        let isSepolia: Bool
        
        // Addresses
        let vaultPubKeyECDSA: String
        let vaultEthAddress: String
        let derivedEthAddressFromPubKey: String
        let circleWalletAddress: String
        
        // MSCA Status
        let isMscaDeployed: Bool
        let mscaCodeLength: Int
        let mscaOwner: String?
        
        // Balances
        let mscaUsdcBalance: Decimal
        let mscaEthBalance: Decimal
        let vaultEthBalance: Decimal
        
        // Contract Addresses
        let usdcContractAddress: String
        
        // Validation Results
        let isVaultOwnerOfMsca: Bool?
        let hasEnoughGasInVault: Bool
        let hasUsdcToWithdraw: Bool
        
        func printReport() {
            print("╔══════════════════════════════════════════════════════════════════╗")
            print("║              CIRCLE WITHDRAWAL DIAGNOSTIC REPORT                 ║")
            print("╠══════════════════════════════════════════════════════════════════╣")
            print("║ Timestamp: \(timestamp)")
            print("╠══════════════════════════════════════════════════════════════════╣")
            print("║ CHAIN CONFIGURATION                                              ║")
            print("║   Chain: \(chainName)")
            print("║   Is Sepolia: \(isSepolia)")
            print("║   USDC Contract: \(usdcContractAddress)")
            print("╠══════════════════════════════════════════════════════════════════╣")
            print("║ ADDRESSES                                                        ║")
            print("║   Vault PubKey ECDSA: \(vaultPubKeyECDSA)")
            print("║   Vault ETH Address (from coins): \(vaultEthAddress)")
            print("║   Derived ETH Address (from pubkey): \(derivedEthAddressFromPubKey)")
            print("║   Address Match: \(vaultEthAddress.lowercased() == derivedEthAddressFromPubKey.lowercased() ? "✅ YES" : "❌ NO - MISMATCH!")")
            print("║   Circle MSCA Wallet: \(circleWalletAddress)")
            print("╠══════════════════════════════════════════════════════════════════╣")
            print("║ MSCA STATUS                                                      ║")
            print("║   Is Deployed On-Chain: \(isMscaDeployed ? "✅ YES" : "❌ NO")")
            print("║   Contract Code Length: \(mscaCodeLength) bytes")
            print("║   MSCA Owner: \(mscaOwner ?? "❓ UNKNOWN (could not fetch)")")
            if let isOwner = isVaultOwnerOfMsca {
                print("║   Vault is Owner: \(isOwner ? "✅ YES" : "❌ NO - PERMISSION DENIED!")")
            } else {
                print("║   Vault is Owner: ❓ COULD NOT VERIFY")
            }
            print("╠══════════════════════════════════════════════════════════════════╣")
            print("║ BALANCES                                                         ║")
            print("║   MSCA USDC Balance: \(mscaUsdcBalance) USDC")
            print("║   MSCA ETH Balance: \(mscaEthBalance) ETH")
            print("║   Vault ETH Balance (for gas): \(vaultEthBalance) ETH")
            print("║   Has USDC to Withdraw: \(hasUsdcToWithdraw ? "✅ YES" : "❌ NO")")
            print("║   Has ETH for Gas: \(hasEnoughGasInVault ? "✅ YES" : "⚠️ LOW/NONE")")
            print("╠══════════════════════════════════════════════════════════════════╣")
            print("║ QUICK DIAGNOSIS                                                  ║")
            if !isMscaDeployed {
                print("║   ❌ MSCA not deployed - Backend needs to run transferNativeOwnership")
            }
            if let isOwner = isVaultOwnerOfMsca, !isOwner {
                print("║   ❌ Vault is NOT the owner - Cannot call execute()")
            }
            if !hasUsdcToWithdraw {
                print("║   ❌ No USDC in MSCA to withdraw")
            }
            if !hasEnoughGasInVault {
                print("║   ⚠️ Vault may not have enough ETH for gas")
            }
            if isMscaDeployed && (isVaultOwnerOfMsca ?? false) && hasUsdcToWithdraw && hasEnoughGasInVault {
                print("║   ✅ All checks passed - Withdrawal should work")
            }
            print("╚══════════════════════════════════════════════════════════════════╝")
        }
    }
    
    // MARK: - Diagnostic Function
    func runDiagnostics(vault: Vault, withdrawAmount: BigInt? = nil) async -> CircleDiagnosticReport {
        print("\n🔍 Running Circle Withdrawal Diagnostics...\n")
        
        // 1. Determine Chain
        let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
        let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
        
        // USDC Constants
        let usdcMainnet = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
        let usdcSepolia = "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"
        let usdcContract = isSepolia ? usdcSepolia : usdcMainnet
        
        // 2. Get Addresses
        let vaultEthAddress = vault.coins.first(where: { $0.chain == chain })?.address ?? ""
        let circleWalletAddress = vault.circleWalletAddress ?? ""
        
        // Derive ETH address from pubkey for comparison
        var derivedAddress = ""
        if let pubKeyData = Data(hexString: vault.pubKeyECDSA),
           let publicKey = PublicKey(data: pubKeyData, type: .secp256k1) {
            derivedAddress = AnyAddress(publicKey: publicKey, coin: .ethereum).description
        }
        
        // 3. Initialize default values
        var isMscaDeployed = false
        var mscaCodeLength = 0
        var mscaOwner: String? = nil
        var mscaUsdcBalance: Decimal = .zero
        var mscaEthBalance: Decimal = .zero
        var vaultEthBalance: Decimal = .zero
        var isVaultOwnerOfMsca: Bool? = nil
        
        // 4. Run checks
        do {
            let service = try EvmService.getService(forChain: chain)
            
            // Check if MSCA is deployed
            if !circleWalletAddress.isEmpty {
                let code = try await service.getCode(address: circleWalletAddress)
                mscaCodeLength = code.count
                isMscaDeployed = code != "0x" && code.count > 2
                
                // Try to get MSCA owner (ERC-173 standard: owner())
                if isMscaDeployed {
                    mscaOwner = await fetchMscaOwner(service: service, mscaAddress: circleWalletAddress)
                    if let owner = mscaOwner {
                        isVaultOwnerOfMsca = owner.lowercased() == vaultEthAddress.lowercased()
                    }
                }
                
                // Get MSCA balances
                if let nativeCoin = vault.coins.first(where: { $0.chain == chain && $0.isNativeToken }) {
                    let usdcVal = try await service.fetchERC20TokenBalance(contractAddress: usdcContract, walletAddress: circleWalletAddress)
                    let ethValStr = try await service.getBalance(coin: nativeCoin.toCoinMeta(), address: circleWalletAddress)
                    let ethVal = BigInt(ethValStr) ?? 0
                    
                    mscaUsdcBalance = (Decimal(string: String(usdcVal)) ?? 0) / pow(10, 6)
                    mscaEthBalance = (Decimal(string: String(ethVal)) ?? 0) / pow(10, 18)
                }
            }
            
            // Get Vault ETH balance (for gas)
            if let nativeCoin = vault.coins.first(where: { $0.chain == chain && $0.isNativeToken }) {
                let vaultEthValStr = try await service.getBalance(coin: nativeCoin.toCoinMeta(), address: vaultEthAddress)
                let vaultEthVal = BigInt(vaultEthValStr) ?? 0
                vaultEthBalance = (Decimal(string: String(vaultEthVal)) ?? 0) / pow(10, 18)
            }
            
        } catch {
            print("CircleViewLogic: Diagnostic error: \(error)")
        }
        
        let report = CircleDiagnosticReport(
            timestamp: Date(),
            chain: chain,
            chainName: chain.name,
            isSepolia: isSepolia,
            vaultPubKeyECDSA: vault.pubKeyECDSA,
            vaultEthAddress: vaultEthAddress,
            derivedEthAddressFromPubKey: derivedAddress,
            circleWalletAddress: circleWalletAddress,
            isMscaDeployed: isMscaDeployed,
            mscaCodeLength: mscaCodeLength,
            mscaOwner: mscaOwner,
            mscaUsdcBalance: mscaUsdcBalance,
            mscaEthBalance: mscaEthBalance,
            vaultEthBalance: vaultEthBalance,
            usdcContractAddress: usdcContract,
            isVaultOwnerOfMsca: isVaultOwnerOfMsca,
            hasEnoughGasInVault: vaultEthBalance > 0.001, // At least 0.001 ETH for gas
            hasUsdcToWithdraw: mscaUsdcBalance > 0
        )
        
        report.printReport()
        return report
    }
    
    // MARK: - Helper: Fetch MSCA Owner
    private func fetchMscaOwner(service: EvmService, mscaAddress: String) async -> String? {
        print("CircleViewLogic: Fetching MSCA owner for \(mscaAddress)...")
        let owner = await service.fetchContractOwner(contractAddress: mscaAddress)
        if let owner = owner {
            print("CircleViewLogic: MSCA owner fetched: \(owner)")
        } else {
            print("CircleViewLogic: Could not fetch MSCA owner (contract may not implement owner())")
        }
        return owner
    }
    
    func createWallet(vault: Vault, force: Bool = false) async throws -> String {
        print("CircleViewLogic: createWallet called (force: \(force))")
        
        // Simply use the vault's ETH address - no need to re-derive!
        // Check for Sepolia first, then mainnet
        let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
        let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
        
        guard let ethCoin = vault.coins.first(where: { $0.chain == chain }) else {
            print("CircleViewLogic: ERROR - No ETH coin found in vault!")
            throw CircleServiceError.keysignError("No ETH coin found in vault. Please add Ethereum first.")
        }
        
        print("CircleViewLogic: Using ETH address from vault: \(ethCoin.address)")
        print("CircleViewLogic: Chain: \(chain.name)")
        
        return try await CircleApiService.shared.createWallet(ethAddress: ethCoin.address, force: force)
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
            
            // Yield data is NOT available from Circle public API
            // Return nil/empty to hide the yield section until real API exists
            let yield = CircleApiService.CircleYieldResponse(apy: "", totalRewards: "", currentRewards: "")
            
            return (usdcBalance, ethBalance, yield)
            
        } catch {
            print("CircleViewLogic: Failed to fetch balance. Error: \(error)")
            // For UI stability, returning 0 with error log is often better for "view" logic.
            return (.zero, .zero, CircleApiService.CircleYieldResponse(apy: "", totalRewards: "", currentRewards: ""))
        }
    }
    
    struct CircleWithdrawalInfo {
        let usdcContract: String
    }

    func getWithdrawalPayload(vault: Vault, recipient: String, amount: BigInt, isNative: Bool = false) async throws -> KeysignPayload {
        print("\n")
        print("════════════════════════════════════════════════════════════════════")
        print("  CIRCLE WITHDRAWAL - STARTING PAYLOAD GENERATION")
        print("════════════════════════════════════════════════════════════════════")
        
        // Run full diagnostics first
        let diagnostics = await runDiagnostics(vault: vault, withdrawAmount: amount)
        
        print("\n📋 Withdrawal Request Details:")
        print("   Circle MSCA Address: \(vault.circleWalletAddress ?? "nil")")
        print("   Recipient: \(recipient)")
        print("   Amount (raw units): \(amount)")
        print("   Amount (USDC): \(Decimal(string: String(amount)) ?? 0 / pow(10, 6))")
        print("   Is Native ETH: \(isNative)")
        
        guard let circleWalletAddress = vault.circleWalletAddress else {
            print("❌ ERROR: Missing Circle Wallet Address in vault")
            throw CircleServiceError.keysignError("Missing Circle Wallet Address")
        }
        
        // 1. Determine Chain and Contracts
        let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
        let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
        
        let usdcMainnet = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
        let usdcSepolia = "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"
        let usdcContract = isSepolia ? usdcSepolia : usdcMainnet
        
        print("\n🔗 Chain Configuration:")
        print("   Chain: \(chain.name)")
        print("   Is Sepolia: \(isSepolia)")
        print("   USDC Contract: \(usdcContract)")
        
        let withdrawalInfo = CircleWithdrawalInfo(usdcContract: usdcContract)
        
        // 2. Build Execution Data (CircleService)
        print("\n🔧 Building execute() calldata...")
        let (to, value, data) = try await CircleService.shared.getWithdrawalValues(
            vault: vault,
            recipientAddress: recipient,
            amount: amount,
            info: withdrawalInfo,
            isNative: isNative
        )
        
        // 3. Fetch Gas Info (EvmService)
        let service = try EvmService.getService(forChain: chain)
        
        // FIXED: Use dynamic chain variable instead of hardcoded .ethereum
        let senderAddress = vault.coins.first(where: { $0.chain == chain })?.address ?? ""
        if senderAddress.isEmpty {
            print("❌ ERROR: Missing ETH Address for chain \(chain.name)")
            throw CircleServiceError.keysignError("Missing ETH Address for \(chain.name)")
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // DETAILED TRANSACTION BREAKDOWN
        // ═══════════════════════════════════════════════════════════════════
        print("")
        print("╔══════════════════════════════════════════════════════════════════╗")
        print("║           WITHDRAWAL TRANSACTION BREAKDOWN                       ║")
        print("╠══════════════════════════════════════════════════════════════════╣")
        print("║")
        print("║ 🔐 WHO SIGNS THE TRANSACTION?")
        print("║    Signer (from): \(senderAddress)")
        print("║    This is your VULTISIG WALLET")
        print("║    Your Vultisig keys will sign this transaction")
        print("║")
        print("║ 📩 WHO RECEIVES THE CALL?")
        print("║    Contract (to): \(to)")
        print("║    This is the CIRCLE MSCA (Smart Contract Account)")
        print("║    The MSCA holds your deposited USDC")
        print("║")
        print("║ 📝 WHAT FUNCTION IS BEING CALLED?")
        print("║    Function: execute(address target, uint256 value, bytes data)")
        print("║    Selector: 0xb61d27f6")
        print("║")
        print("║ 📦 INNER CALL (what execute() will do):")
        print("║    Target: \(usdcContract) (USDC Contract)")
        print("║    Function: transfer(address to, uint256 amount)")
        print("║    Recipient: \(recipient)")
        print("║    Amount: \(amount) (\(Decimal(string: String(amount))! / pow(10, 6)) USDC)")
        print("║")
        print("║ 🔄 FLOW:")
        print("║    1. Vultisig (\(senderAddress.prefix(10))...) SIGNS tx")
        print("║    2. Tx sent TO Circle MSCA (\(to.prefix(10))...)")
        print("║    3. MSCA.execute() is called")
        print("║    4. MSCA verifies caller is authorized (owner check)")
        print("║    5. If authorized → MSCA calls USDC.transfer()")
        print("║    6. USDC moves from MSCA to recipient")
        print("║")
        print("║ ⚠️  KEY QUESTION:")
        print("║    Does the MSCA recognize \(senderAddress.prefix(10))... as owner?")
        print("║    If NOT → Step 4 fails → 'execution reverted'")
        print("║")
        print("╠══════════════════════════════════════════════════════════════════╣")
        print("║ RAW TRANSACTION DATA:")
        print("║   To: \(to)")
        print("║   Value: \(value) wei")
        print("║   Data length: \(data.count) bytes")
        print("║   Data: \(data.hexString.prefix(66))...")
        print("╚══════════════════════════════════════════════════════════════════╝")
        print("")
        
        // Use FAST fee mode for Circle withdrawals to ensure quick confirmation
        let (gasPrice, priorityFee, nonce) = try await service.getGasInfo(fromAddress: senderAddress, mode: .fast)
        
        // Apply boost for faster confirmation
        // Ensure max fee is at least 2 Gwei, and priority fee is reasonable
        let minMaxFee = BigInt(2_000_000_000) // 2 Gwei minimum
        let boostedGasPrice = max(gasPrice * 2, minMaxFee)  // 2x or at least 2 Gwei
        
        // Priority fee must be LESS than or EQUAL to max fee
        let desiredPriorityFee = max(priorityFee * 2, BigInt(100_000_000)) // 2x or at least 0.1 Gwei
        let boostedPriorityFee = min(desiredPriorityFee, boostedGasPrice) // Cap at max fee
        
        print("\n⛽ Gas Information (BOOSTED for fast confirmation):")
        print("   Original Gas Price: \(gasPrice) wei (\(Double(gasPrice.description) ?? 0 / 1_000_000_000) Gwei)")
        print("   Boosted Max Fee: \(boostedGasPrice) wei (\(Double(boostedGasPrice.description) ?? 0 / 1_000_000_000) Gwei)")
        print("   Original Priority Fee: \(priorityFee) wei")
        print("   Boosted Priority Fee: \(boostedPriorityFee) wei (\(Double(boostedPriorityFee.description) ?? 0 / 1_000_000_000) Gwei)")
        print("   Priority <= MaxFee: \(boostedPriorityFee <= boostedGasPrice ? "✅ YES" : "❌ NO")")
        print("   Nonce: \(nonce)")
        
        // Fix Data hex string (RPC expects 0x prefix)
        var dataHex = data.hexString
        if !dataHex.hasPrefix("0x") {
            dataHex = "0x" + dataHex
        }
        if dataHex == "0x" { // Check if empty data
             dataHex = "0x"
        }
        
        // CHECK: Verify if the Circle Wallet is deployed
        print("\n🔍 Verifying MSCA Deployment...")
        let code = try await service.getCode(address: to)
        let isDeployed = code != "0x" && code.count > 2
        print("   Target Address: \(to)")
        print("   Contract Code Length: \(code.count) characters")
        print("   Is Deployed: \(isDeployed ? "✅ YES" : "❌ NO")")
        
        if !isDeployed {
            print("\n❌ FATAL: Circle MSCA is not deployed on-chain!")
            print("   The backend needs to execute transferNativeOwnership to deploy the MSCA.")
            print("   Please contact the backend team with this diagnostic report.")
            throw CircleServiceError.keysignError("Circle Wallet is not deployed on-chain yet. Please contact support.")
        }
        
        // Estimate Gas
        print("\n📊 Estimating Gas Limit...")
        print("   Simulating transaction:")
        print("     From: \(senderAddress)")
        print("     To: \(to)")
        print("     Value: \(value)")
        print("     Data: \(dataHex.prefix(66))...")
        
        do {
            let gasLimit = try await service.estimateGasLimitForSwap(
                senderAddress: senderAddress,
                toAddress: to,
                value: value,
                data: dataHex
            )
            
            print("   ✅ Gas Estimated Successfully: \(gasLimit)")
            print("\n════════════════════════════════════════════════════════════════════")
            print("  GAS ESTIMATION PASSED - Transaction should succeed")
            print("════════════════════════════════════════════════════════════════════\n")
            
            // 4. Construct Keysign Payload
            guard let coin = vault.coins.first(where: { $0.chain == chain && $0.isNativeToken }) else {
                print("❌ ERROR: Missing native coin for chain \(chain.name)")
                throw CircleServiceError.keysignError("Missing ETH Coin")
            }
            
            let chainSpecific = BlockChainSpecific.Ethereum(
                maxFeePerGasWei: boostedGasPrice,
                priorityFeeWei: boostedPriorityFee,
                nonce: nonce,
                gasLimit: gasLimit
            )
            
            // Use GenericSwapPayload to carry the execution data
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
            
            print("✅ KeysignPayload constructed successfully")
            return payloadWithData
            
        } catch {
            print("\n❌ GAS ESTIMATION FAILED!")
            print("   Error: \(error)")
            print("\n   This usually means one of:")
            print("   1. The sender (\(senderAddress)) is NOT the owner of the MSCA")
            print("   2. The MSCA doesn't have enough USDC balance")
            print("   3. The transaction would revert for another reason")
            print("\n   Please check the diagnostic report above and contact backend team.")
            throw error
        }
    }
}

