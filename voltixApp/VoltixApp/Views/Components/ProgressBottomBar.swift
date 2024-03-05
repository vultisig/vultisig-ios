    //
    //  ProgressBottomBar.swift
    //  VoltixApp
    //
    //  Created by dev on 09.02.2024.
    //

import SwiftUI

struct ProgressBottomBar: View {
    let content: String;
    let onClick: () -> Void;
    let progress: Int;
    let showProgress: Bool;
    let showButton: Bool;
    
    init(
        content: String,
        onClick: @escaping () -> Void,
        progress: Int,
        showProgress: Bool = false,
        showButton: Bool = true
    ) {
        self.content = content
        self.onClick = onClick
        self.progress = progress
        self.showProgress = showProgress
        self.showButton = showButton
    }
    var body: some View {
        HStack() {
            if showProgress {
                GeometryReader { geometry in
                    HStack(alignment: .center, spacing: 10) {
                        ForEach(0..<5) { index in
                            HStack {
                                Rectangle()
                                    .foregroundColor(.clear)
                                    .frame(width: (geometry.size.width - 150) * 0.2, height: 5)
                                    .overlay(Rectangle()
                                        .stroke(self.barColor(index: index), lineWidth: 5))
                            }
                            .padding(.leading, 30)
                            .cornerRadius(12)
                        }
                    }
                    .frame(width: .infinity, height: 70)
                }
            }
            Spacer()
            if self.showButton {
                Button(action: onClick) {
                    HStack() {
                        Spacer()
                        Text(content)
                            .lineSpacing(60)
                            .font(.title40MenloBlack)
                        
                            .padding(.trailing, 16)
                        Image(systemName: "chevron.right")
                            .resizable()
                            .frame(width: 20, height: 30)
                    }
                }
                .frame(width: 350)
                .buttonStyle(PlainButtonStyle())
            }
            else {
                Spacer().frame(width: 350)
            }
        }
        .padding(.trailing, 16)
        .frame(width: .infinity, height: 70)
    }
    
    func barColor(index: Int) -> Color {
        if index < progress {
            return .black
        } else {
            return Color.gray500
        }
    }
}

#Preview {
    ProgressBottomBar(
        content: "CONTINUE",
        onClick: {
            
        },
        progress: 1
    )
}
