//
//  SwapCryptoDoneView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-04.
//

import SwiftUI
import RiveRuntime

struct SwapCryptoDoneView: View {
    @State var animationVM: RiveViewModel? = nil
    
    var body: some View {
        VStack {
            cards
            buttons
        }
        .onAppear {
            animationVM = RiveViewModel(fileName: "vaultCreatedAnimation", autoPlay: true)
        }
    }
    
    var cards: some View {
        ScrollView {
            animation
            fromToCards
        }
    }
    
    var buttons: some View {
        HStack(spacing: 8) {
            trackButton
            doneButton
        }
        .padding(.vertical)
        .background(Color.backgroundBlue)
    }
    
    var trackButton: some View {
        Button {
            
        } label: {
            trackLabel
        }
    }
    
    var trackLabel: some View {
        FilledButton(
            title: "track",
            textColor: .neutral0,
            background: .blue400
        )
    }
    
    var doneButton: some View {
        Button {
            
        } label: {
            doneLabel
        }
    }
    
    var doneLabel: some View {
        FilledButton(
            title: "done",
            textColor: .neutral0,
            background: .persianBlue400
        )
    }
    
    var animation: some View {
        ZStack {
            animationVM?.view()
                .frame(width: 280, height: 280)
            
            animationText
                .offset(y: 50)
        }
    }
    
    var animationText: some View {
        Text(NSLocalizedString("transactionSuccesful", comment: ""))
            .foregroundStyle(LinearGradient.primaryGradient)
            .font(.body18BrockmannMedium)
    }
    
    var fromToCards: some View {
        ZStack {
            HStack(spacing: 8) {
                getFromToCard(
                    icon: "THORChain",
                    title: "1,000.12 RUNE",
                    description: "1,250.52 $"
                )
                
                getFromToCard(
                    icon: "THORChain",
                    title: "1,000.12 RUNE",
                    description: "1,250.52 $"
                )
            }
            
            chevronContent
        }
    }
    
    var chevronContent: some View {
        ZStack {
            chevronIcon
            
            filler
                .offset(y: -24)
            
            filler
                .offset(y: 24)
            
        }
    }
    
    var chevronIcon: some View {
        Image(systemName: "chevron.right")
            .foregroundColor(.disabledText)
            .font(.body12Menlo)
            .bold()
            .frame(width: 24, height: 24)
            .background(Color.blue600)
            .cornerRadius(60)
            .padding(8)
            .background(Color.backgroundBlue)
            .cornerRadius(60)
            .overlay(
                Circle()
                    .stroke(Color.blue200, lineWidth: 1)
            )
    }
    
    var filler: some View {
        Rectangle()
            .frame(width: 8, height: 18)
            .foregroundColor(Color.backgroundBlue)
    }
    
    private func getFromToCard(icon: String, title: String, description: String) -> some View {
        VStack(spacing: 4) {
            Image(icon)
                .resizable()
                .frame(width: 36, height: 36)
                .padding(.bottom, 8)
            
            Text(title)
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)
            
            Text(description)
                .font(.body10BrockmannMedium)
                .foregroundColor(.extraLightGray)
        }
        .frame(height: 130)
        .frame(maxWidth: .infinity)
        .background(Color.blue600)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue200, lineWidth: 1)
        )
    }
}

#Preview {
    SwapCryptoDoneView()
}
