//
//  EmptyPeerCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-29.
//

import SwiftUI
import RiveRuntime

struct EmptyPeerCell: View {
    let counter: Int
    
    @State var isPhone: Bool = false
    @State var animationVM: RiveViewModel? = nil
    
    var body: some View {
        cell
            .onAppear {
                animationVM = RiveViewModel(fileName: "WaitingForDevice", autoPlay: true)
            }
            .onDisappear {
                animationVM?.stop()
            }
    }
    
    var cell: some View {
        VStack(alignment: .leading, spacing: 0) {
            animation
            Spacer()
            text
        }
        .padding(16)
        .frame(
            width: 150,
            height: 100
        )
        .background(Color.blue600)
        .cornerRadius(10)
        .overlay (
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.borderBlue, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
        .padding(1)
    }
    
    var text: some View {
        Group {
            Text(NSLocalizedString("scanWith", comment: "")) +
            Text(" " + getDeviceNumber() + " ") +
            Text(NSLocalizedString("device", comment: ""))
        }
        .font(.body14BrockmannMedium)
        .foregroundColor(.neutral0)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var animation: some View {
        animationVM?.view()
            .frame(width: 24, height: 24)
    }
    
    private func getDeviceNumber() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        let number = NSNumber(value: counter+1)
        return formatter.string(from: number) ?? "First"
    }
}

#Preview {
    EmptyPeerCell(counter: 0)
}
