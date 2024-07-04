//
//  MemoTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-04.
//

import SwiftUI

struct MemoTextField: View {
    @Binding var memo: String
    
    @Environment(\.isEnabled) private var isEnabled
    
    var body: some View {
        ZStack(alignment: .trailing) {
            if memo.isEmpty {
                Text(NSLocalizedString("enterMemo", comment: ""))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack(spacing: 0) {
                TextField(NSLocalizedString("enterMemo", comment: "").capitalized, text: $memo)
                    .borderlessTextFieldStyle()
                    .submitLabel(.next)
                    .disableAutocorrection(true)
                    .textFieldStyle(TappableTextFieldStyle())
                    .foregroundColor(isEnabled ? .neutral0 : .neutral300)
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif
            }
        }
        .font(.body12Menlo)
        .foregroundColor(.neutral0)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(10)
    }
}

#Preview {
    MemoTextField(memo: .constant(""))
}
