//
//  CounterView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

import SwiftUI

struct CounterView: View {
    @Binding var count: Int
    let minimumValue: Int
    
    private var disabled: Bool { count == minimumValue }
    
    init(count: Binding<Int>, minimumValue: Int) {
        self._count = count
        self.minimumValue = minimumValue
    }
    
    var body: some View {
        HStack {
            counterButton(icon: "minus.circle") {
                count -= 1
            }
            .disabled(disabled)
            .opacity(disabled ? 0.2 : 1)
            
            counterContainer {
                Text("\(count)")
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(.clear)
                    .font(.body16BrockmannMedium)
            }
            
            counterButton(icon: "plus.circle") {
                count += 1
            }
        }
    }
    
    func counterButton(icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            counterContainer {
                Image(systemName: icon)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.blue600)
                    .font(.body22BrockmannMedium)
            }
        }
    }
    
    @ViewBuilder
    func counterContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            content()
        }
        .foregroundColor(.neutral0)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue400, lineWidth: 1)
        )
    }
}

#Preview {
    CounterView(count: .constant(5), minimumValue: 1)
}
