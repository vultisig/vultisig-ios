//
//  FinishedTSSKeygenView.swift
//  VoltixApp
//

import SwiftUI

struct FinishedTSSKeygenView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @Environment(\.modelContext) private var context
    @EnvironmentObject var appState: ApplicationState
    @ObservedObject var vault: Vault
    
    @State private var isBackuped = false
    @State private var isRadioAllChecked = false
    @State private var checkbox1 = false
    @State private var checkbox2 = false
    @State private var checkbox3 = false
    
    
    var body: some View {
        VStack {
            HeaderView(
                rightIcon: "QuestionMark",
                leftIcon: "",
                head: "DONE",
                leftAction: {
                    if !self.presentationStack.isEmpty {
                        self.presentationStack.removeLast()
                    }
                },
                rightAction: {
                    // open help modal
                }
            )
            VStack {
                AddressItem(coinName: "Bitcoin", address: "bc1psrjtwm7682v6nhx2uwfgcfelrennd7pcvqq7v6w")
                Spacer()
                BottomBar(content: "BACKUP", onClick: {
                    // to do some actions for backup
                    isBackuped = true;
                })
            }
            .frame(width: Utils.isIOS() ? .infinity : 1050, height: 400)
            
            Spacer()
            if isBackuped {
                VStack(alignment: .trailing) {
                    HStack {
                        Spacer()
                        radioButton(
                            1,
                            callback: self.radioButtonCallback,
                            isSelected: self.checkbox1,
                            textSize: Utils.isIOS() ? 13 : 24,
                            text: "I’VE SAVED A BACKUP OF THE VAULT"
                        )
                    }
                    HStack {
                        Spacer()
                        radioButton(
                            2,
                            callback: self.radioButtonCallback,
                            isSelected: self.checkbox2,
                            textSize: Utils.isIOS() ? 13 : 24,
                            text: "NOBODY BUT ME CAN ACCESS THE BACKUP"
                        )
                    }
                    HStack {
                        Spacer()
                        radioButton(
                            3,
                            callback: self.radioButtonCallback,
                            isSelected: self.checkbox3,
                            textSize: Utils.isIOS() ? 13 : 24,
                            text: "IT’S NOT LOCATED WITH THE OTHER BACKUPS"
                        )
                    }
                }
                .frame(width: .infinity, height: 160)
            }
            ProgressBottomBar(
                content: "FINISH",
                onClick: self.FinishClicked,
                progress: 5,
                showProgress: !Utils.isIOS(),
                showButton: self.isRadioAllChecked
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
        .onAppear(){
            for item in vault.keyshares {
                print("pubkey:\(item.pubkey) , share:\(item.keyshare)")
            }
        }
        .navigationBarBackButtonHidden(true)
    }
    
    private func radioButtonCallback(id: Int) {
        switch id {
            case 1:
                self.checkbox1 = !self.checkbox1;
            case 2:
                self.checkbox2 = !self.checkbox2;
            case 3:
                self.checkbox3 = !self.checkbox3;
        default:
            break;
        }
        self.isRadioAllChecked = self.checkbox1 && self.checkbox2 && self.checkbox3;
    }
    
    private func FinishClicked() {
        self.presentationStack = [.vaultSelection]
    }
}

#Preview {
    FinishedTSSKeygenView(presentationStack: .constant([]), vault: Vault(name: "my vault"))
}
