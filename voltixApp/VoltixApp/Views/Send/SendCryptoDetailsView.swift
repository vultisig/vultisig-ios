//
//  SendCryptoDetailsView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import SwiftUI

struct SendCryptoDetailsView: View {
    @State var toAddress = ""
    @State var amount = ""
    
    var body: some View {
        ZStack {
            background
            view
        }
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var view: some View {
        VStack {
            fields
            button
        }
    }
    
    var fields: some View {
        ScrollView {
            VStack(spacing: 16) {
                coinSelector
                fromField
                toField
                amountField
                gasField
            }
            .padding(.horizontal, 16)
        }
    }
    
    var coinSelector: some View {
        HStack(spacing: 12) {
            Image("eth")
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(100)
            
            Text("Ethereum")
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
            
            Spacer()
            
            Text("23.2")
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
            
            Image(systemName: "chevron.down")
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
        }
        .frame(height: 48)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    var fromField: some View {
        VStack(spacing: 8) {
            getTitle(for: "from")
            fromTextField
        }
    }
    
    var fromTextField: some View {
        Text("0x0cb1D4a24292bB89862f599Ac5B10F42b6DE07e4")
            .font(.body12Menlo)
            .foregroundColor(.neutral0)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Color.blue600)
            .cornerRadius(10)
    }
    
    var toField: some View {
        VStack(spacing: 8) {
            getTitle(for: "to")
            toTextField
        }
    }
    
    var toTextField: some View {
        ZStack(alignment: .trailing) {
            if toAddress.isEmpty {
                Text(NSLocalizedString("enterAddress", comment: ""))
                    .foregroundColor(Color.neutral0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack(spacing: 0) {
                TextField(NSLocalizedString("enterAddress", comment: "").capitalized, text: $toAddress)
                    .foregroundColor(.neutral0)
                    .submitLabel(.next)
                
                scanButton
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
    
    var scanButton: some View {
        Image(systemName: "camera")
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .frame(width: 40, height: 40)
    }
    
    var amountField: some View {
        VStack(spacing: 8) {
            getTitle(for: "amount")
            amountTextField
        }
    }
    
    var amountTextField: some View {
        ZStack(alignment: .trailing) {
            if amount.isEmpty {
                Text(NSLocalizedString("enterAmount", comment: ""))
                    .foregroundColor(Color.neutral0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack(spacing: 0) {
                TextField(NSLocalizedString("enterAmount", comment: "").capitalized, text: $amount)
                    .foregroundColor(.neutral0)
                    .submitLabel(.next)
                
                maxButton
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
    
    var maxButton: some View {
        Text(NSLocalizedString("max", comment: "").uppercased())
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .frame(width: 40, height: 40)
    }
    
    var gasField: some View {
        HStack {
            Text(NSLocalizedString("gas(auto)", comment: ""))
            Spacer()
            Text("$4.00")
        }
        .font(.body16Menlo)
        .foregroundColor(.neutral0)
    }
    
    var button: some View {
        FilledButton(title: "continue")
            .padding(40)
    }
    
    private func getTitle(for text: String) -> some View {
        Text(NSLocalizedString(text, comment: ""))
            .font(.body14MontserratMedium)
            .foregroundColor(.neutral0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
    }
}

#Preview {
    SendCryptoDetailsView()
}
