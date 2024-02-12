//
//  NewWalletInstructions.swift
//  VoltixApp
//

import SwiftData
import SwiftUI

struct NewWalletInstructions: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @State  var vaultName:String
    
    
    var body: some View {
        #if os(iOS)
        smallScreen(presentationStack: $presentationStack)
        #else
        LargeScreen(presentationStack: $presentationStack)
        #endif
    }
}

private struct smallScreen: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: ApplicationState
    @Query var vaults: [Vault]
    
    var body: some View {
        VStack() {
            HeaderView(
              rightIcon: "QuestionMark",
              leftIcon: "BackArrow",
              head: "SETUP",
              leftAction: {
                  if !self.presentationStack.isEmpty {
                      self.presentationStack.removeLast()
                  }
              },
              rightAction: {}
            )
            Text("YOU NEED THREE DEVICES.")
              .font(Font.custom("Montserrat", size: 24).weight(.medium))
              .lineSpacing(36)
              .foregroundColor(.black);
            DeviceView(
                number: "1",
                description: "MAIN",
                deviceImg: "Device1",
                deviceDescription: "A MACBOOK"
            )
            Spacer()
            DeviceView(
                number: "2",
                description: "PAIR",
                deviceImg: "Device2",
                deviceDescription: "ANY"
            )
            Spacer()
            DeviceView(
                number: "3",
                description: "PAIR",
                deviceImg: "Device3",
                deviceDescription: "ANY"
            )
            WifiBar()
            BottomBar(content: "CONTINUE", onClick: {
                let vault = Vault(name: "Vault #\(vaults.count + 1)")
                appState.creatingVault = vault
                self.presentationStack.append(.peerDiscovery)
            })
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

private struct LargeScreen: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @State private var radioClicked: Bool = false
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: ApplicationState
    @Query var vaults: [Vault]
    
    var body: some View {
        VStack() {
            LargeHeaderView(
                presentationStack:$presentationStack,
              rightIcon: "QuestionMark",
              leftIcon: "BackArrow",
              head: "SETUP",
              leftAction: {
                  if !self.presentationStack.isEmpty {
                      self.presentationStack.removeLast()
                  }
              },
              rightAction: {},
              back: true
            )
            Text("YOU NEED A MACBOOK AND TWO PAIR DEVICES.")
              .font(Font.custom("Montserrat", size: 24).weight(.medium))
              .lineSpacing(36)
              .foregroundColor(.black);
            Spacer().frame(height: 30)
            HStack {
                Spacer()
                DeviceView(
                    number: "1",
                    description: "MAIN",
                    deviceImg: "Device1",
                    deviceDescription: "A MACBOOK"
                )
                Spacer()
                DeviceView(
                    number: "2",
                    description: "PAIR DEVICE",
                    deviceImg: "Device2",
                    deviceDescription: "ANY APPLE DEVICE"
                )
                Spacer()
                DeviceView(
                    number: "3",
                    description: "PAIR DEVICE",
                    deviceImg: "Device3",
                    deviceDescription: "ANY APPLE DEVICE"
                )
                Spacer()
            }
            Spacer()
            ZStack {
              WifiBar()
              VStack {
                HStack {
                  Spacer()
                    radioButton(
                        1,
                        callback: self.radioButtonCallback,
                        isSelected: self.radioClicked,
                        text: "THIS IS THE MAIN DEVICE"
                    )
                }
              }
              .frame(width: .infinity, height: 100)
            }
            .frame(width: .infinity, height: 100)
            ProgressBottomBar(
                content: "CONTINUE",
                onClick: { 
                    let vault = Vault(name: "Vault #\(vaults.count + 1)")
                    appState.creatingVault = vault
                    self.presentationStack.append(.peerDiscovery)
                },
                progress: 1,
                showProgress: true
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
        .navigationBarBackButtonHidden()
    }
    func radioButtonCallback(id: Int) {
        self.radioClicked = !self.radioClicked
    }
}

#Preview {
    NewWalletInstructions(presentationStack: .constant([]),vaultName: "")
}
