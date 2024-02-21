import SwiftUI

struct SendVerifyView: View {
    @Binding var presentationStack: [CurrentScreen]
    @ObservedObject var viewModel: SendTransaction
    
    @State private var isChecked1 = false
    @State private var isChecked2 = false
    @State private var isChecked3 = false
    
    private var isValidForm : Bool {
        return isChecked1 && isChecked2 && isChecked3
    }
    
    var body: some View {
        VStack{
            Form { // Define spacing if needed
                LabelText(title: "FROM", value: viewModel.fromAddress).padding(.vertical, 10)
                LabelText(title: "TO", value: viewModel.toAddress).padding(.vertical, 10)
                LabelTextNumeric(title: "AMOUNT", value: viewModel.amount + " BTC").padding(.vertical, 10)
                LabelText(title: "MEMO", value: viewModel.memo).padding(.vertical, 10)
                LabelTextNumeric(title: "FEE", value: viewModel.gas).padding(.vertical, 10)
            }
            
            Group{
                VStack {
                    Toggle("I'M SENDING TO THE RIGHT ADDRESS", isOn: $isChecked1)
                        .toggleStyle(CheckboxToggleStyle())
                    
                    Toggle("THE AMOUNT IS CORRECT", isOn: $isChecked2)
                        .toggleStyle(CheckboxToggleStyle())
                    
                    Toggle("I'M NOT BEING HACKED OR PHISHED", isOn: $isChecked3)
                        .toggleStyle(CheckboxToggleStyle())
                }
                .padding()
            }.padding(.vertical)
            
            Spacer()
            
            Group{
                HStack{
                    Spacer()
                    
                    Text(isValidForm ? "" : "* You must agree with the terms.")
                        .font(Font.custom("Montserrat", size: 13)
                            .weight(.medium))
                        .padding(.vertical, 5)
                        .foregroundColor(.red)
                    BottomBar(
                        content: "SIGN",
                        onClick: {
                            
                        }
                    )
                }
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
    
    // Helper view for label and value text
    @ViewBuilder
    private func LabelTextNumeric(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(Font.custom("Menlo", size: 20).weight(.bold))
            Spacer()
            Text(value)
                .font(Font.custom("Menlo", size: 30).weight(.ultraLight))
                .padding(.vertical, 5)
            Spacer()
        }
    }
}

// Custom ToggleStyle for Checkbox appearance
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        return HStack {
            Spacer()
            configuration.label
            Image(systemName: configuration.isOn ? "circle.dashed.inset.filled" : "circle.dashed")
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundColor(configuration.isOn ? Color.primary : Color.secondary)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
        }
    }
}

struct SendVerifyView_Previews: PreviewProvider {
    static var previews: some View {
        SendVerifyView(presentationStack: .constant([]), viewModel: SendTransaction(fromAddress: "3JK2dFmWA58A3kukgw1yybotStGAFaV6Sg", toAddress: "3JK2dFmWA58A3kukgw1yybotStGAFaV6Sg", amount: "100", memo: "Test Memo", gas: "0.01"))
    }
}
