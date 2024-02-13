//
//  ImportWallet.swift
//  VoltixApp
//

import SwiftUI

struct ImportWalletView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @State var vaultShare = ""
    
    var body: some View {
        #if os(iOS)
            smallScreen(presentationStack: $presentationStack)
        #else
            largeScreen(presentationStack: $presentationStack)
        #endif
    }
}
 
private struct smallScreen: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @State private var vaultText = "";
    var body: some View {
        VStack {
            HeaderView(
                rightIcon: "QuestionMark",
                leftIcon: "BackArrow",
                head: "IMPORT",
                leftAction: {
                    if !self.presentationStack.isEmpty {
                        self.presentationStack.removeLast()
                    }
                },
                rightAction: {
                    
                }
            )
            Spacer().frame(height: 30)
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    TextEditor(text: $vaultText)
                        .font(.custom("AmericanTypewriter", fixedSize: 24))
                        .scrollContentBackground(.hidden)
                        .foregroundColor(.black)
                    HStack {
                        Button(action : {

                        }) {
                            Image("Camera")
                        }
                        .padding(.trailing,  8)
                        .buttonStyle(PlainButtonStyle())
                        Button(action : {
                            
                        }) {
                            Image("Doc")
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .foregroundColor(.clear)
                .frame(width: .infinity, height: 326)
                .padding()
                .background(Color(red: 0.96, green: 0.96, blue: 0.96))
                .cornerRadius(12)
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            Spacer()
            BottomBar(
                content: "CONTINUE",
                onClick: {
                    self.presentationStack.append(.newWalletInstructions)
                }
            )
        }
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: 0,
            maxHeight: .infinity,
            alignment: .top
        )
        .background(.white)
    }
}

private struct largeScreen: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @State private var vaultText = ""
    @State private var isloaded: Bool = false
    
    var body: some View {
        VStack {
            LargeHeaderView(
                rightIcon: "QuestionMark",
                leftIcon: "BackArrow",
                head: "IMPORT",
                leftAction: {
                    if !self.presentationStack.isEmpty {
                        self.presentationStack.removeLast()
                    }
                },
                rightAction: {
                    
                },
                back: true
            )
            Spacer().frame(height: 30);
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    TextEditor(text: $vaultText)
                        .font(.custom("AmericanTypewriter", fixedSize: 50))
                        .scrollContentBackground(.hidden)
                        .foregroundColor(.black)
                    HStack {
                        Button(action : {}) {
                            Image("Camera")
                        }
                        .padding(.trailing,  8)
                        .buttonStyle(PlainButtonStyle())
                        Button(action : {}) {
                            Image("Doc")
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .foregroundColor(.clear)
                .frame(width: .infinity, height: 326)
                .padding()
                .background(Color(red: 0.96, green: 0.96, blue: 0.96))
                .cornerRadius(12)
                Text("ENTER YOUR PREVIOUSLY CREATED VAULT SHARE")
                  .font(Font.custom("Montserrat", size: 30).weight(.medium))
                  .lineSpacing(40)
                  .foregroundColor(.black)
            }
            .padding(.leading, 30)
            .padding(.trailing, 30)
            Spacer()
            if isloaded {
                BottomBar(
                    content: "CONTINUE",
                    onClick: {
                        self.presentationStack.append(.vaultSelection)
                    }
                )
            }
        }
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: 0,
            maxHeight: .infinity,
            alignment: .top
        )
        .background(.white)
        .navigationBarBackButtonHidden()
    }
}

#Preview {
    ImportWalletView(presentationStack: .constant([]))
}
