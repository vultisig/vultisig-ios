//
//  KeygenViewInstructionsMac.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-08.
//

import SwiftUI

struct KeygenViewInstructionsMac: View {
    @State var tabIndex = 0

    var body: some View {
        content
    }

    var content: some View {
        ZStack {
            ForEach(0..<7) { index in
                getCard(for: index)
            }
            .allowsHitTesting(false)

            controls
        }
        .frame(maxWidth: .infinity)
        .foregroundColor(.blue)
    }

    var controls: some View {
        HStack {
            previousButton
            Spacer()
            nextButton
        }
        .padding(.horizontal, 30)
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
    }

    var previousButton: some View {
        let isDisabled = tabIndex==0

        return Button(action: {
            withAnimation {
                tabIndex -= 1
            }
        }, label: {
            NavigationButton(isLeft: true)
        })
        .disabled(isDisabled)
        .opacity(isDisabled ? 0 : 1)
    }

    var nextButton: some View {
        let isDisabled = tabIndex==6

        return Button(action: {
            withAnimation {
                tabIndex += 1
            }
        }, label: {
            NavigationButton()
        })
        .disabled(isDisabled)
        .opacity(isDisabled ? 0 : 1)
    }

    private func getCard(for index: Int) -> some View {
        VStack(spacing: 22) {
            getTitle(for: index)
            getDescription(for: index)
        }
        .tag(index)
        .frame(maxWidth: 420)
        .opacity(index==tabIndex ? 1 : 0)
    }

    private func getTitle(for index: Int) -> some View {
        Text(NSLocalizedString("keygenInstructionsCar\(index+1)Title", comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodyMMedium)
    }

    private func getDescription(for index: Int) -> some View {
        Group {
            Text(NSLocalizedString("keygenInstructionsCar\(index+1)DescriptionPart1", comment: ""))
                .foregroundColor(Theme.colors.textPrimary)
                .font(Theme.fonts.caption12) +
            Text(NSLocalizedString("keygenInstructionsCar\(index+1)DescriptionPart2", comment: ""))
                .foregroundColor(Theme.colors.bgButtonPrimary)
                .font(Theme.fonts.caption12) +
            Text(NSLocalizedString("keygenInstructionsCar\(index+1)DescriptionPart3", comment: ""))
                .foregroundColor(Theme.colors.textPrimary)
                .font(Theme.fonts.caption12)
        }
        .multilineTextAlignment(.center)
    }
}

#Preview {
    KeygenViewInstructionsMac()
}
