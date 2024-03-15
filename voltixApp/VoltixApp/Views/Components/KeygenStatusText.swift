    //
    //  KeygenStatusText.swift
    //  VoltixApp
    //
    //  Created by Enrique Souza Soares on 22/02/2024.
    //

import Foundation
import SwiftUI

struct KeyGenStatusText: View {
    let status: String
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Text(self.status)
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(2)
                Spacer()
            }.padding(.vertical, 30)
        }
        .cornerRadius(10)
        .shadow(radius: 5)
        .padding()
    }
}
