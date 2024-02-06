//
//  Logo.swift
//  VoltixApp
//
//  Created by Mac on 05.02.2024.
//

import SwiftUI

struct Logo: View {
    let width: CGFloat;
    let height: CGFloat;
    var body: some View {
        Image("Logo")
            .resizable()
            .frame(width: width, height: height)
    }
}

#Preview {
    Logo(width: 100, height: 100)
}
