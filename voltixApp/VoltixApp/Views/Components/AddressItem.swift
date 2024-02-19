//
//  AdressItem.swift
//  VoltixApp
//
//  Created by Mac on 05.02.2024.
//

import SwiftUI

struct AddressItem: View {
    let coinName: String;
    let address: String;

    var body: some View {
        #if os(iOS)
        samllItem(coinName: self.coinName, address: self.address)
        #else
        largeItem(coinName: self.coinName, address: self.address)
        #endif
    }
}

private struct samllItem: View {
    let coinName: String;
    let address: String;

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(coinName)
                .font(Font.custom("Menlo", size: 20).weight(.bold))
                .lineSpacing(30)
                
                .padding(.bottom, 5)
                Text(address)
                .font(Font.custom("Montserrat", size: 13).weight(.medium))
                .lineLimit(1)
                .lineSpacing(19.50)
                
            }
            .foregroundColor(.clear)
            .frame(width: .infinity, height: 70)
            .padding(.leading, 10)
            Spacer()
            Button(action: {}) {
                Image("Copy")
                .resizable()
                .frame(width: 32, height: 30)
            }
            
            .frame(width: 50, height: 30)
            .buttonStyle(PlainButtonStyle())
            .offset(x: 0, y: 10)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 0)
    }
}

private struct largeItem: View {
    let coinName: String;
    let address: String;

    var body: some View {
        HStack {
            Text(coinName)
            .font(Font.custom("Menlo", size: 40).weight(.bold))
            .lineSpacing(60)
            
            .padding(.bottom, 5)
            Text(address)
            .font(Font.custom("Montserrat", size: 24).weight(.medium))
            .lineLimit(1)
            .lineSpacing(36)
            
            .frame(width: 700)
            Button(action: {}) {
                Image("Copy")
                .resizable()
                .frame(width: 32, height: 30)
            }
            
            .frame(width: 50, height: 30)
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.trailing, 16)
        .padding(.bottom, 0)
    }
}


#Preview {
    AddressItem(coinName: "Bitcoin", address: "bc1psrjtwm7682v6nhx2uwfgcfelrennd7pcvqq7v6w")
}
