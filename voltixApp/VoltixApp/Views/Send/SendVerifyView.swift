import SwiftUI

struct SendVerifyView: View {
    @Binding var presentationStack: [CurrentScreen]
    @ObservedObject var viewModel: TransactionDetailsViewModel
    
    var body: some View {
        
        GeometryReader { geometry in
            VStack(alignment: .leading) {
                Group {
                    VStack(alignment: .leading) {
                        Text("FROM")
                            .font(.system(size: geometry.size.width * 0.05, weight: .bold))
                            .foregroundColor(.black)
                        // Assuming FROM address might be static or fetched elsewhere; update accordingly
                        Text(viewModel.fromAddress)
                            .font(.system(size: geometry.size.width * 0.04))
                            .foregroundColor(.black)
                    }
                    VStack(alignment: .leading) {
                        Text("TO")
                            .font(.system(size: geometry.size.width * 0.05, weight: .bold))
                            .foregroundColor(.black)
                        // Dynamically display the TO address from the view model
                        Text(viewModel.toAddress)
                            .font(.system(size: geometry.size.width * 0.04))
                            .foregroundColor(.black)
                    }
                    HStack {
                        Text("AMOUNT")
                            .font(.system(size: geometry.size.width * 0.05, weight: .bold))
                            .foregroundColor(.black)
                        Spacer()
                        // Dynamically display the AMOUNT from the view model
                        Text(viewModel.amount + " BTC")
                            .font(.system(size: geometry.size.width * 0.08, weight: .light))
                            .foregroundColor(.black)
                    }
                    VStack(alignment: .leading) {
                        Text("MEMO")
                            .font(.system(size: geometry.size.width * 0.05, weight: .bold))
                            .foregroundColor(.black)
                        // Dynamically display the MEMO from the view model
                        Text(viewModel.memo)
                            .font(.system(size: geometry.size.width * 0.04))
                            .foregroundColor(.black)
                    }
                    HStack {
                        Text("Fee")
                            .font(.system(size: geometry.size.width * 0.05, weight: .bold))
                            .foregroundColor(.black)
                        Spacer()
                        // Dynamically display the GAS from the view model
                        Text("$" + viewModel.gas) // Assuming the gas is stored as a string; adjust as necessary
                            .font(.system(size: geometry.size.width * 0.08, weight: .light))
                            .foregroundColor(.black)
                    }
                }
                .frame(height: geometry.size.height * 0.1)
                Spacer()
                Group {
                    // RadioButtonGroup and BottomBar as before
                }
            }
            .padding(.leading, geometry.size.width * 0.05)
            .navigationTitle("SEND")
            .navigationBarBackButtonHidden()
            .modifier(InlineNavigationBarTitleModifier())
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationButtons.backButton(presentationStack: $presentationStack)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationButtons.questionMarkButton
                }
#else
                ToolbarItem {
                    NavigationButtons.backButton(presentationStack: $presentationStack)
                }
                ToolbarItem {
                    NavigationButtons.questionMarkButton
                }
#endif
            }
        }
    }
}

// Preview
struct SendVerifyView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a dummy ViewModel for preview purposes
        let viewModel = TransactionDetailsViewModel()
        viewModel.toAddress = "0xF42b6DE07e40cb1D4a24292bB89862f599Ac5B10"
        viewModel.amount = "1.0"
        viewModel.memo = "TEST"
        viewModel.gas = "4.00"
        
        return SendVerifyView(presentationStack: .constant([]), viewModel: viewModel)
    }
}
