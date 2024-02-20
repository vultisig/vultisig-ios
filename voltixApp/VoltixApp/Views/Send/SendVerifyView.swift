import SwiftUI

struct SendVerifyView: View {
    @Binding var presentationStack: [CurrentScreen]
    @ObservedObject var viewModel: SendTransaction
    
    var body: some View {
        VStack{
            Form { // Define spacing if needed
                LabelText(title: "FROM", value: viewModel.fromAddress).padding(.vertical, 10)
                LabelText(title: "TO", value: viewModel.toAddress).padding(.vertical, 10)
                LabelText(title: "AMOUNT", value: viewModel.amount + " BTC").padding(.vertical, 10)
                LabelText(title: "MEMO", value: viewModel.memo).padding(.vertical, 10)
                LabelText(title: "FEE", value: "$" + viewModel.gas).padding(.vertical, 10)
            }
            
            Group{
                RadioButtonGroup(
                    items: [
                        "I'M SENDING TO THE RIGHT ADDRESS",
                        "THE AMOUNT IS CORRECT",
                        "I'M NOT BEING HACKED OR PHISHED",
                    ],
                    selectedId: "I'M SENDING TO THE RIGHT ADDRESS"
                ) {
                    selected in print("Selected is: \(selected)")
                }
            }.padding(.vertical)
            
            Spacer()
            
            Group{
                BottomBar(
                    content: "SIGN",
                    onClick: {
                        
                    }
                )
            }
        }
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
#Preview{
    SendVerifyView(presentationStack: .constant([]), viewModel: SendTransaction())
}
