import SwiftUI

struct TransactionMemoView: View {
    @State private var selectedTransactionType: TransactionMemoType = .swap
    
    var body: some View {
        VStack {
            Picker("Select Transaction Type", selection: $selectedTransactionType) {
                ForEach(TransactionMemoType.allCases) { type in
                    Text(type.rawValue.capitalized).tag(type)
                }
            }
            
            DynamicFormView(viewModel: selectedTransactionType.viewModel())
        }
    }
}

#Preview {
    TransactionMemoView()
}
