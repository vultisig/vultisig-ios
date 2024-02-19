//
//  ToastView.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 14/02/2024.
//

import Foundation
import SwiftUI

struct ToastView: View {
    var message: String
    
    var body: some View {
        Text(message)
            .padding()
            .background(Color.black.opacity(0.7))
            .cornerRadius(8)
    }
}
