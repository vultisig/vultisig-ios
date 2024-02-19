import SwiftUI

struct SendVerifyView: View {
    @Binding var presentationStack: [CurrentScreen]
    @ObservedObject var viewModel: SendTransaction
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                VStack(alignment: .leading, spacing: 8) { // Define spacing if needed
                    LabelText(title: "FROM", value: viewModel.fromAddress).padding(.vertical, 10)
                    LabelText(title: "TO", value: viewModel.toAddress).padding(.vertical, 10)
                    LabelText(title: "AMOUNT", value: viewModel.amount + " BTC").padding(.vertical, 10)
                    LabelText(title: "MEMO", value: viewModel.memo).padding(.vertical, 10)
                    LabelText(title: "FEE", value: "$" + viewModel.gas).padding(.vertical, 10)
                    // Your RadioButtonGroup and BottomBar here
                }
                .padding(.all) // Ensure padding is applied to the VStack directly
                
                .navigationTitle("VERIFY")
                .navigationBarBackButtonHidden(true)
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
    
    // Helper view for label and value text
    @ViewBuilder
    private func LabelText(title: String, value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(Font.custom("Menlo", size: 20).weight(.bold))
            Text(value)
                .font(Font.custom("Montserrat", size: 13).weight(.medium))
                .padding(.vertical, 5)
        }
    }
}

// Ensure NavigationButtons are correctly implemented
