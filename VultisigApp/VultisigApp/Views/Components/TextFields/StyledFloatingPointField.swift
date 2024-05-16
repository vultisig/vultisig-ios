//
//  StyledFloatingPointField.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import Foundation
import SwiftUI

struct StyledFloatingPointField<Value: BinaryFloatingPoint & Codable>: View {
    let placeholder: String
    @Binding var value: Value
    let format: FloatingPointFormatStyle<Value>
    
    var body: some View {
        TextField(placeholder.capitalized, value: $value, format: format)
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .submitLabel(.done)
            .padding(12)
            .background(Color.blue600)
            .cornerRadius(12)
    }
}
