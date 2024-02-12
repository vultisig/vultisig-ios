//
//  StartView.swift
//  VoltixApp
//

import SwiftUI
import OSLog

private let logger = Logger(subsystem: "peers-discory", category: "communication")
struct StartView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        #if os(iOS)
            startSmallScreen(presentationStack: $presentationStack)
        #else
            startLargeScreen(presentationStack: $presentationStack)
        #endif
    }
}

struct startSmallScreen: View {
    @Binding var presentationStack: Array<CurrentScreen>
    var body: some View {
        VStack() {
            HeaderView(
                rightIcon: "QuestionMark",
                leftIcon: "BackArrow",
                head: "START",
                leftAction: {
                    if !self.presentationStack.isEmpty {
                        self.presentationStack.removeLast()
                    }
                },
                rightAction: {}
            )
            Spacer()
            VStack() {
                LargeButton(content: "NEW", onClick: {
                    self.presentationStack.append(.newWalletInstructions)
                })
                Text("CREATE A NEW VAULT")
                  .font(Font.custom("Montserrat", size: 24).weight(.medium))
                  .lineSpacing(36)
                  .foregroundColor(.black);

            }
            .frame(width: .infinity, height: .infinity)
            Spacer()
            VStack() {
                LargeButton(content: "IMPORT", onClick: {
                    self.presentationStack.append(.importWallet)
                })
                Text("IMPORT AN EXSTING VAULT")
                  .font(Font.custom("Montserrat", size: 24).weight(.medium))
                  .lineSpacing(36)
                  .foregroundColor(.black);
            }
            .frame(width: .infinity, height: .infinity)
            Spacer()
        }
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: 0,
            maxHeight: .infinity,
            alignment: .top
        )
    }
}

struct startLargeScreen: View {
    @Binding var presentationStack: Array<CurrentScreen>
    var body: some View {
        VStack() {
            HeaderView(
                rightIcon: "QuestionMark",
                leftIcon: "BackArrow",
                head: "START",
                leftAction: {
                    if !self.presentationStack.isEmpty {
                        self.presentationStack.removeLast()
                    }
                },
                rightAction: {}
            )
            Spacer()
            GeometryReader { geometry in
                HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/) {
                    VStack() {
                        LargeButton(content: "NEW", onClick: {
                            self.presentationStack.append(.newWalletInstructions)
                        })
                        Text("CREATE A NEW VAULT")
                          .font(Font.custom("Montserrat", size: 24).weight(.medium))
                          .padding(.top, 8)
                          .foregroundColor(.black);

                    }
                    .frame(width: geometry.size.width * 0.5)
                    VStack() {
                        LargeButton(content: "IMPORT", onClick: {
                            self.presentationStack.append(.importWallet)
                        })
                        Text("IMPORT AN EXISTING VAULT")
                          .font(Font.custom("Montserrat", size: 24).weight(.medium))
                          .padding(.top, 8)
                          .foregroundColor(.black);
                    }
                    .frame(width: geometry.size.width * 0.5)
                }
            }.frame(height: 391)
            Spacer()
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


#Preview {
    StartView(presentationStack: .constant([]))
}
