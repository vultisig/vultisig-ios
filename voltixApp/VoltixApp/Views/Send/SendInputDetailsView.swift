import SwiftUI

// Assuming CurrentScreen is an enum that you've defined elsewhere

struct SendInputDetailsView: View {
    @Binding var presentationStack: [CurrentScreen]
    @ObservedObject var unspentOutputsViewModel: UnspentOutputsViewModel
    @ObservedObject var transactionDetailsViewModel: TransactionDetailsViewModel

    var body: some View {
        GeometryReader { geometry in
            VStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text("BTC")
                            .font(.system(size: geometry.size.width * 0.05, weight: .bold))
                            .foregroundColor(.black)
                        
                        Spacer()
                        
                        if let walletData = unspentOutputsViewModel.walletData {
                            Text(String(walletData.balanceInBTC))
                                .padding().font(.system(size: geometry.size.width * 0.05))
                                .foregroundColor(.black)
                        } else {
                            Text("Error to fetch the data")
                                .padding()
                        }
                    }
                    .onAppear {
                        if unspentOutputsViewModel.walletData == nil {
                            Task {
                                await unspentOutputsViewModel.fetchUnspentOutputs(for: $transactionDetailsViewModel.fromAddress.wrappedValue)
                            }
                        }
                    }
                    .padding()
                    .frame(height: geometry.size.height * 0.07)
                    
                    Group {
                        inputField(title: "To", text: $transactionDetailsViewModel.toAddress, geometry: geometry)
                        inputField(title: "Amount", text: $transactionDetailsViewModel.amount, geometry: geometry, isNumeric: true)
                        inputField(title: "Memo", text: $transactionDetailsViewModel.memo, geometry: geometry)
                        gasField(geometry: geometry)
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    BottomBar(content: "CONTINUE", onClick: {
                        // Update this logic as necessary to navigate to the SendVerifyView
                        // self.presentationStack.append(contentsOf: .sendVerifyScreen(transactionDetailsViewModel))
                    
                        self.presentationStack.append(.sendVerifyScreen(transactionDetailsViewModel))
                    })
                    .padding(.horizontal)
                }
                .navigationBarBackButtonHidden()
                .navigationTitle("SEND")
                .modifier(InlineNavigationBarTitleModifier())
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        NavigationButtons.backButton(presentationStack: $presentationStack)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationButtons.questionMarkButton
                    }
                }
            }
        }
    }
    
    private func inputField(title: String, text: Binding<String>, geometry: GeometryProxy, isNumeric: Bool = false) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.system(size: geometry.size.width * 0.05, weight: .bold))
                .foregroundColor(.black)
            TextField("", text: text)
                .padding()
                .background(Color(red: 0.92, green: 0.92, blue: 0.93))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray, lineWidth: 1)
                )
        }
        .frame(height: geometry.size.height * 0.12)
    }
    
    private func gasField(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading) {
            Text("Gas")
                .font(.system(size: geometry.size.width * 0.05, weight: .bold))
                .foregroundColor(.black)
            Spacer()
            HStack {
                TextField("", text: $transactionDetailsViewModel.gas)
                    .padding()
                    .background(Color(red: 0.92, green: 0.92, blue: 0.93))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray, lineWidth: 1)
                    )
                Spacer()
                Text("$4.00")
                    .font(.system(size: geometry.size.width * 0.05, weight: .bold))
                    .foregroundColor(.black)
            }
        }
        .frame(height: geometry.size.height * 0.12)
    }
}

// Preview
struct SendInputDetailsView_Previews: PreviewProvider {
    static var previews: some View {
        SendInputDetailsView(presentationStack: .constant([]), unspentOutputsViewModel: UnspentOutputsViewModel(), transactionDetailsViewModel: TransactionDetailsViewModel())
    }
}
