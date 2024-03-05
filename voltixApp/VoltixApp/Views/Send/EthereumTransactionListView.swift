    //
    //  VoltixApp
    //
    //  Created by Enrique Souza Soares
    //
import SwiftUI

struct EthereumTransactionListView: View {
    @StateObject var etherScanService: EtherScanService = EtherScanService()
    @EnvironmentObject var appState: ApplicationState
    @Binding var presentationStack: [CurrentScreen]
    @State var contractAddress: String?
    
    var body: some View {
        VStack {
            List {
                if let transactions = etherScanService.transactions {
                    if let addressFor = etherScanService.addressFor {
                        ForEach(transactions, id: \.hash) { transaction in
                            EthTransactionRow(transaction: transaction, myAddress: addressFor)
                        }
                    }
                } else if let errorMessage = etherScanService.errorMessage {
                    Text("Error fetching transactions: \(errorMessage)")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Transactions")
            .navigationBarBackButtonHidden()
            .modifier(InlineNavigationBarTitleModifier())
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationButtons.backButton(presentationStack: $presentationStack)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationButtons.questionMarkButton
                }
            }
            .task {
                if let vault = appState.currentVault {
                    
                    let result = EthereumHelper.getEthereum(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
                    
                    switch result {
                        case .success(let eth):
                            if let contract = contractAddress {
                                await etherScanService.fetchERC20Transactions(
                                    forAddress: eth.address,
                                    apiKey: AppConfiguration.etherScanApiKey,
                                    contractAddress: contract
                                )
                                
                            } else {
                                await etherScanService.fetchTransactions(forAddress: eth.address, apiKey: AppConfiguration.etherScanApiKey)
                            }
                        case .failure(let error):
                            print("error: \(error)")
                    }
                    
                }
            }
        }
    }
}

struct EthTransactionRow: View {
    let transaction: TransactionDetail
    let myAddress: String
    
    var body: some View {
        Section {
            VStack(alignment: .leading) {
                
                LabelTxHash(title: "TX ID:".uppercased(), value: transaction.hash ?? "", isSent: self.myAddress.lowercased() != transaction.to.lowercased())
                    .padding(.vertical, 5)
                Divider()
                
                LabelText(title: "From:".uppercased(), value: transaction.from)
                    .padding(.vertical, 1)
                Divider()
                
                LabelText(title: "To:".uppercased(), value: transaction.to)
                    .padding(.vertical, 1)
                Divider()
                
                let decimals: Int = Int(transaction.tokenDecimal ?? "18") ?? 18
                let etherValue = convertToEther(fromWei: transaction.value, decimals)
                LabelTextNumeric(title: "Amount \(transaction.tokenSymbol ?? "ETH"):".uppercased(), value: etherValue)
                    .padding(.vertical, 1)
                    //                Divider()
                    //
                    //                LabelTextNumeric(title: "Gas Used:".uppercased(), value: transaction.gasUsed)
                    //                    .padding(.vertical, 5)
                
                Divider()
                
                let feeDisplay = calculateTransactionFee(gasUsed: transaction.gasUsed ?? "", gasPrice: transaction.gasPrice)
                LabelTextNumeric(title: "Fee Paid:".uppercased(), value: feeDisplay)
                    .padding(.vertical, 5)
            }
        }
    }
    
    @ViewBuilder
    private func LabelTxHash(title: String, value: String, isSent: Bool) -> some View {
        let url = Endpoint.ethereumLabelTxHash(value)
        
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: isSent ? "arrowtriangle.up.square" : "arrowtriangle.down.square")
                    .resizable()
                    .frame(width: 20, height: 20)
                
                Text(title)
                    .font(.body20MenloBold)
            }
            Link(destination: URL(string: url)!) {
                Text(value)
                    .font(.body13MontserratMedium)
                    .padding(.vertical, 5)
                    .foregroundColor(Color.blue)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    @ViewBuilder
    private func LabelText(title: String, value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.body20MenloBold)
            Text(value)
                .font(.body13MontserratMedium)
                .padding(.vertical, 5)
        }
    }
    
    @ViewBuilder
    private func LabelTextNumeric(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.body20MenloBold)
            Spacer()
            Text(value)
                .font(.title30MenloUltraLight)
                .padding(.vertical, 5)
        }
    }
    
    private func convertToEther(fromWei value: String, _ decimals: Int = 18) -> String {
        if let wei = Double(value) {
            let ether = wei / pow(10.0, Double(decimals)) // Correctly perform exponentiation
            return String(format: "%.4f", ether)
        } else {
            return "Invalid Value"
        }
    }
    
    private func calculateTransactionFee(gasUsed: String, gasPrice: String) -> String {
        guard let gasUsedDouble = Double(gasUsed), let gasPriceDouble = Double(gasPrice) else {
            return "Invalid Data"
        }
        
            // Calculate the fee in Wei
        let feeInWei = gasUsedDouble * gasPriceDouble
        
            // Convert the fee from Wei to Ether
        let feeInEther = feeInWei / 1_000_000_000_000_000_000
        
            // Format the result to a string with a suitable number of decimal places
        return String(format: "%.6f ETH", feeInEther)
    }
}
