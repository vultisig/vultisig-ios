//
//  AddressBookTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-11.
//

import SwiftUI

struct AddressBookTextField: View {
    let title: String
    @Binding var text: String
    var showActions = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleContent
            textField
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var titleContent: some View {
        Text(NSLocalizedString(title, comment: ""))
            .foregroundColor(Color.neutral0)
            .font(.body14MontserratMedium)
    }
    
    var textField: some View {
        field
            .font(.body12Menlo)
            .foregroundColor(.neutral0)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Color.blue600)
            .cornerRadius(10)
            .colorScheme(.dark)
    }
    
    var placeholder: some View {
        Text(NSLocalizedString("typeHere", comment: ""))
            .foregroundColor(Color.neutral0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var field: some View {
        HStack(spacing: 0) {
            TextField(NSLocalizedString("typeHere", comment: "").capitalized, text: $text)
            .foregroundColor(.neutral0)
            .submitLabel(.next)
            .disableAutocorrection(true)
            .borderlessTextFieldStyle()
#if os(iOS)
            .keyboardType(.default)
            .textInputAutocapitalization(.never)
            .textContentType(.oneTimeCode)
#endif
        }
    }
   
}

#Preview {
    ZStack {
        Background()
        AddressBookTextField(title: "title", text: .constant(""))
    }
}
