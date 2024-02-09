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
    var body: some View {
        HStack() {
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
            Spacer()
            Button(action: onClick) {
                HStack() {
                    Spacer()
                    Text(content)
                      .lineSpacing(60)
                      .font(Font.custom("Menlo", size: 40).weight(.black))
                      .foregroundColor(.black)
                      .padding(.trailing, 16)
                    Image(systemName: "chevron.right")
                      .resizable()
                      .foregroundColor(.black)
                      .frame(width: 20, height: 30)
                }
            }
            .frame(width: 350)
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.trailing, 16)
        .frame(width: .infinity, height: 70)
    }
    
    func barColor(index: Int) -> Color {
        if index < progress {
            return .black
        } else {
            return Color(red: 0.96, green: 0.96, blue: 0.96)
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
