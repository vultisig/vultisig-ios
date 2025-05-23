//
//  SwiftUIView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-26.
//

import SwiftUI

import SwiftUI

struct ErrorMessage: View {
    let text: String
    var width: CGFloat = 200
    var typewriterSpeed: Double = 0.03

    @State private var revealedText: String = ""
    @State private var timer: Timer? = nil

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.body24MontserratBold)
                .foregroundColor(.alertYellow)
            Text(revealedText)
                .font(.body16MenloBold)
                .foregroundColor(.alertYellow)
                .multilineTextAlignment(.center)
                .frame(maxWidth: width)
        }
        .onAppear {
            startTypewriterEffect()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
            revealedText = ""
        }
    }

    private func startTypewriterEffect() {
        revealedText = ""
        let fullText = NSLocalizedString(text, comment: "")
        var currentIndex = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: typewriterSpeed, repeats: true) { t in
            if currentIndex < fullText.count {
                let idx = fullText.index(fullText.startIndex, offsetBy: currentIndex + 1)
                revealedText = String(fullText[..<idx])
                currentIndex += 1
            } else {
                t.invalidate()
                timer = nil
            }
        }
    }

    var logo: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.body24MontserratBold)
            .foregroundColor(.alertYellow)
    }

    var title: some View {
        Text(NSLocalizedString(text, comment: ""))
            .font(.body16MenloBold)
            .foregroundColor(.alertYellow)
            .multilineTextAlignment(.center)
    }
}

#Preview {
    ZStack {
        Background()
        ErrorMessage(text: "signInErrorTryAgain")
    }
}
