    //
    //  AssetsView.swift
    //  VoltixApp
    //
    //  Created by Mac on 05.02.2024.
    //

import SwiftUI

struct AssetsView: View {
    let numberOfAssets: String;
    var body: some View {
        VStack() {
            Text(numberOfAssets + " Assets")
                .font(Font.custom("Montserrat", size: 18).weight(.medium))
                .lineSpacing(27)
        }
        .frame(width: 122.71, height: 25)
        .cornerRadius(20)
    }
}

#Preview {
    AssetsView(numberOfAssets: "3")
}
