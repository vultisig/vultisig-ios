import SwiftUI
import Foundation

struct CoinDetailView: View {
    let coin: Coin
    @ObservedObject var group: GroupedChain
    let vault: Vault
    @StateObject var sendTx: SendTransaction
    @Binding var resetActive: Bool
    
    @State var isLoading = false
    @State var isLoadingBonds = false
    
    @State var isSendLinkActive = false
    @State var isSwapLinkActive = false
    @State var isMemoLinkActive = false
    
    @Environment(\.router) var router
    
    var body: some View {
        content
            .navigationDestination(isPresented: $isSwapLinkActive) {
                SwapCryptoView(fromCoin: coin, vault: vault)
            }
            .navigationDestination(isPresented: $isMemoLinkActive) {
                FunctionCallView(
                    tx: sendTx,
                    vault: vault,
                    coin: coin
                )

            }
            .navigationDestination(isPresented: $isSendLinkActive) {
                SendRouteBuilder().buildDetailsScreen(coin: coin, hasPreselectedCoin: true, tx: sendTx, vault: vault)
            }
            .onAppear {
                sendTx.reset(coin: coin)
            }
            .task {
                if coin.isRune {
                    await fetchBondData()
                }
            }
            .onChange(of: isMemoLinkActive) { oldValue, newValue in
                if newValue {
                    sendTx.coin = coin
                }
            }
            .onChange(of: isSendLinkActive) { oldValue, newValue in
                if newValue {
                    sendTx.reset(coin: coin)
                }
            }
    }
       
    var actionButtons: some View {
        ChainDetailActionButtons(
            isChainDetail: true,
            group: group,
            isLoading: $isLoading,
            isSendLinkActive: $isSendLinkActive,
            isSwapLinkActive: $isSwapLinkActive,
            isMemoLinkActive: $isMemoLinkActive
        )
    }
    
    var cells: some View {
        VStack(spacing: 16) {
            cell
            
            if coin.isRune && coin.hasBondedNodes {
                bondCells
            } else if coin.isRune && isLoadingBonds {
                ProgressView()
                    .padding(.vertical, 8)
            }
        }
        .cornerRadius(10)
    }
    
    var cell: some View {
        CoinCell(coin: coin)
    }
    
    @State private var selectedBondNode: RuneBondNode?
    @State private var selectedMemoNodeMaintenance: FunctionCallNodeMaintenance?
    
    var bondCells: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(coin.bondedNodes.indices, id: \ .self) { index in
                let node = coin.bondedNodes[index]
                Group {
                    if index > 0 {
                        Separator()
                    }
                    RuneBondCell(bondNode: node, coin: coin)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let status = node.status.lowercased()
                            let action: FunctionCallNodeMaintenance.NodeAction =
                                (status == "active") ? .bond : .unbond
                            let memo = FunctionCallNodeMaintenance(nodeAddress: node.address, action: action)
                            selectedMemoNodeMaintenance = memo
                            selectedBondNode = node
                            
                            sendTx.memoFunctionDictionary = memo.toDictionary()
                            
                            isMemoLinkActive = true
                        }
                }
            }
        }
    }
    
    func refreshData() async {
        isLoading = true
        await BalanceService.shared.updateBalance(for: coin)
        
        if coin.isRune {
            await fetchBondData()
        }
        
        isLoading = false
    }
    
    func fetchBondData() async {
        isLoadingBonds = true
        
        if let address = coin.address.isEmpty ? nil : coin.address {
            let bondedNodes = await ThorchainService.shared.fetchRuneBondNodes(address: address)
            coin.bondedNodes = bondedNodes
        }
        
        isLoadingBonds = false
    }
}

