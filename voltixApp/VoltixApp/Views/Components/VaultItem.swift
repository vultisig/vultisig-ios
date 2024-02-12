//
//  VaultItem.swift
//  VoltixApp
//
//  Created by Mac on 05.02.2024.
//

import SwiftUI

struct VaultItem: View {
    let coinName: String;
    let amount: String;
    let showAmount: Bool;
    let coinAmount: String;
    let address: String;
    let isRadio: Bool;
    let radioIcon: String;
    let showButtons: Bool;
    let onClick: () -> Void;
    init(
        coinName: String,
        amount: String,
        showAmount: Bool = true,
        coinAmount: String = "1.1",
        address: String,
        isRadio: Bool = false,
        radioIcon: String = "largecircle.fill.circle",
        showButtons: Bool = false,
        onClick: @escaping () -> Void
    ) {
        self.coinName = coinName
        self.amount = amount
        self.showAmount = showAmount
        self.coinAmount = coinAmount
        self.address = address
        self.isRadio = isRadio
        self.radioIcon = radioIcon
        self.showButtons = showButtons
        self.onClick = onClick
    }
    
    var body: some View {
        #if os(iOS)
        smallItem(
            coinName: self.coinName,
            amount: self.amount,
            showAmount: self.showAmount,
            coinAmount: self.coinAmount,
            address: self.address,
            isRadio: self.isRadio,
            radioIcon: self.radioIcon,
            showButtons: self.showButtons
        )
        #else
        largeItem(
            coinName: self.coinName,
            amount: self.amount,
            showAmount: self.showAmount,
            coinAmount: self.coinAmount,
            address: self.address,
            isRadio: self.isRadio,
            radioIcon: self.radioIcon,
            showButtons: self.showButtons,
            onClick: self.onClick
        )
        #endif
    }
}


private struct smallItem: View {
    let coinName: String;
    let amount: String;
    let showAmount: Bool;
    let coinAmount: String;
    let address: String;
    let isRadio: Bool;
    let radioIcon: String;
    let showButtons: Bool;
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack() {
                Text(coinName)
                    .font(Font.custom("Menlo", size: 20).weight(.bold))
                    .foregroundColor(.black)
                if showButtons {
                    Spacer().frame(width: 10)
                    Button(action: {}) {
                        Image(systemName: "square.on.square")
                            .resizable()
                            .frame(width: 20, height: 20)
                            .foregroundColor(.black)
                    }
                    Spacer().frame(width: 8)
                    Button(action: {}) {
                        Image(systemName: "square.and.arrow.up")
                            .resizable()
                            .frame(width: 16, height: 20)
                            .foregroundColor(.black)
                    }
                    Spacer().frame(width: 8)
                    Button(action: {}) {
                        Image(systemName: "qrcode")
                            .resizable()
                            .frame(width: 20, height: 20)
                            .foregroundColor(.black)
                    }
                }
                Spacer()
                if showAmount {
                    Text(amount)
                        .font(Font.custom("Menlo", size: 20))
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.black)
                }
                Spacer().frame(width: 16)
                Text("$" + coinAmount)
                    .font(Font.custom("Menlo", size: 20))
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.black)
            }
            HStack() {
                Text(address)
                    .font(Font.custom("Montserrat", size: 13).weight(.medium))
                    .lineSpacing(19.50)
                    .foregroundColor(.black);
                Spacer()
                if isRadio {
                    Image(systemName: radioIcon)
                        .renderingMode(.original)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .modifier(ColorInvert())
                }
            }
        }
        .padding()
        .frame(width: .infinity, height: 83)
    }
}

private struct largeItem: View {
    let coinName: String;
    let amount: String;
    let showAmount: Bool;
    let coinAmount: String;
    let address: String;
    let isRadio: Bool;
    let radioIcon: String;
    let showButtons: Bool;
    let onClick: () -> Void;
    var body: some View {
        HStack() {
            Text(coinName)
                .font(Font.custom("Menlo", size: 32).weight(.bold))
                .foregroundColor(.black)
                .frame(width: 300, alignment: .leading)
                
            Text(address)
                .font(Font.custom("Montserrat", size: 24).weight(.medium))
                .foregroundColor(.black);
            if showButtons {
                Spacer().frame(width: 10)
                Button(action: {}) {
                    Image(systemName: "square.on.square")
                        .resizable()
                        .frame(width: 32, height: 30)
                        .foregroundColor(.black)
                }
                .buttonStyle(PlainButtonStyle())
                Spacer().frame(width: 8)
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                        .resizable()
                        .frame(width: 23.6, height: 30)
                        .foregroundColor(.black)
                }
                .buttonStyle(PlainButtonStyle())
                Spacer().frame(width: 8)
                Button(action: {}) {
                    Image(systemName: "qrcode")
                        .resizable()
                        .frame(width: 30, height: 30)
                        .foregroundColor(.black)
                }
                .buttonStyle(PlainButtonStyle())
            }
            Spacer()
            if showAmount {
                Text(amount)
                    .font(Font.custom("Menlo", size: 32))
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.black)
            }
            Spacer().frame(width: 16)
            Text("$" + coinAmount)
                .font(Font.custom("Menlo", size: 32))
                .multilineTextAlignment(.trailing)
                .foregroundColor(.black)
            if isRadio {
                Button(action: self.onClick) {
                    Image(systemName: "chevron.right")
                        .renderingMode(.original)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 30)
                        .foregroundColor(.black)
                }
            }
        }
        .frame(width: .infinity, height: 83)
        .padding()
    }
}

#Preview {
     VaultItem(
            coinName: "THORChain",
            amount: "11.1",
            coinAmount: "65,899",
            address: "thor1cfelrennd7pcvqq7v6w7682v6nhx2uwfg",
            onClick: {
                
            }
    )
}
