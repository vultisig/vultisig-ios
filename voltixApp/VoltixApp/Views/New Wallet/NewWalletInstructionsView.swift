//
//  NewWalletInstructions.swift
//  VoltixApp
//

import SwiftData
import SwiftUI

struct NewWalletInstructions: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @State  var vaultName:String
    
    let navigationTitle: String = "New wallet"
    
    var body: some View {
        #if os(iOS)
        smallScreen(presentationStack: $presentationStack, navigationTitle: navigationTitle)
        #else
        LargeScreen(presentationStack: $presentationStack, navigationTitle: navigationTitle)
        #endif
    }
}

private struct smallScreen: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: ApplicationState
    @Query var vaults: [Vault]
    
    var navigationTitle: String
    
    var body: some View {
        VStack() {
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
            BottomBar(content: "SEND Input details", onClick: {
                self.presentationStack.append(.sendInputDetails)
            })
            BottomBar(content: "CONTINUE", onClick: {
                let vault = Vault(name: "Vault #\(vaults.count + 1)")
                appState.creatingVault = vault
                self.presentationStack.append(.peerDiscovery)
            })
        }
        .background(.white)
        .navigationTitle(navigationTitle)
        .modifier(InlineNavigationBarTitleModifier())
        .navigationBarBackButtonHidden()
        .toolbar {
          #if os(iOS)
            ToolbarItem(placement: .navigationBarLeading) {
              NavigationButtons.backButton(presentationStack: $presentationStack)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
              NavigationButtons.questionMarkButton
            }
          #else
            ToolbarItem {
              NavigationButtons.backButton(presentationStack: $presentationStack)
            }
            ToolbarItem {
              NavigationButtons.questionMarkButton
            }
          #endif
        }
    }
}

private struct LargeScreen: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @State private var radioClicked: Bool = false
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: ApplicationState
    @Query var vaults: [Vault]
    
    var navigationTitle: String
    
    var body: some View {
        VStack() {
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
        .navigationTitle(navigationTitle)
        .navigationBarBackButtonHidden()
        .modifier(InlineNavigationBarTitleModifier())
        .toolbar {
          #if os(iOS)
            ToolbarItem(placement: .navigationBarLeading) {
              NavigationButtons.backButton(presentationStack: $presentationStack)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
              NavigationButtons.questionMarkButton
            }
          #else
            ToolbarItem {
              NavigationButtons.backButton(presentationStack: $presentationStack)
            }
            ToolbarItem {
              NavigationButtons.questionMarkButton
            }
          #endif
        }
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
