//
//  ChainCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct ChainCell: View {
    let group: GroupedChain
    @Binding var balanceInFiat: String?
    @Binding var isEditingChains: Bool
    @Binding var balanceInDecimal: Decimal?
    
    @State var showAlert = false
    @State var showQRcode = false
    
    @StateObject var viewModel = ChainCellViewModel()
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            rearrange
            logo
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .animation(.easeInOut, value: isEditingChains)
        .onAppear {
            Task {
                await setData()
            }
        }
        .onChange(of: group.coins) { oldValue, newValue in
            Task {
                await setData()
            }
        }
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            address
        }
    }
    
    var rearrange: some View {
        Image(systemName: "line.3.horizontal")
            .font(.body14MontserratMedium)
            .foregroundColor(.neutral100)
            .frame(maxWidth: isEditingChains ? nil : 0)
            .clipped()
    }
    
    var header: some View {
        HStack(spacing: 12) {
            title
            Spacer()
            
            if group.coins.count>1 {
                count
            } else {
                quantity
            }
            
            balance
        }
        .lineLimit(1)
    }
    
    var logo: some View {
        Image(group.logo)
            .resizable()
            .frame(width: 32, height: 32)
            .cornerRadius(50)
    }
    
    var title: some View {
        Text(group.name.capitalized)
            .font(.body16MontserratBold)
            .foregroundColor(.neutral0)
    }
    
    var address: some View {
        Text(group.address)
            .font(.body12Menlo)
            .foregroundColor(.turquoise600)
            .lineLimit(1)
            .truncationMode(.middle)
    }
    
    var count: some View {
        Text(viewModel.getGroupCount(group))
            .font(.body12Menlo)
            .foregroundColor(.neutral100)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.blue400)
            .cornerRadius(50)
    }
    
    var quantity: some View {
        let quantity = viewModel.quantity
        
        return Text(quantity ?? "0.00000")
            .font(.body12Menlo)
            .foregroundColor(.neutral100)
            .redacted(reason: quantity==nil ? .placeholder : [])
    }
    
    var balance: some View {
        let balance = viewModel.balanceInFiat
        let decimalBalance = viewModel.balanceInDecimal
        
        return Text(balance ?? "$0.00000")
            .font(.body16MenloBold)
            .foregroundColor(.neutral100)
            .redacted(reason: balance==nil ? .placeholder : [])
            .onChange(of: balance) { oldValue, newValue in
                balanceInFiat = newValue
            }
            .onChange(of: decimalBalance) { oldValue, newValue in
                balanceInDecimal = newValue
            }
    }
    
    private func setData() async {
        await viewModel.loadData(for: group)
    }
}

#Preview {
    ScrollView {
        ChainCell(group: GroupedChain.example, balanceInFiat: .constant("$65,899"), isEditingChains: .constant(true), balanceInDecimal: .constant(65899))
    }
}
