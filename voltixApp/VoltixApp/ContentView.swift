//
//  ContentView.swift
//  VoltixApp
//
//  Created by Johnny Luo on 28/1/2024.
//

import SwiftUI
import SwiftData
import Mediator

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var vault: [Vault]
    private var mediator = Mediator(serverPort: 8080)
    var body: some View {
        ScrollView{
            HStack{
                Spacer()
                VStack{
                    Spacer()
                    Button(action: {
                        
                    },label: {
                        Label("Hello World",systemImage: "snow")
                    }).padding(5)
                    Spacer()
                }
                Spacer()
            }
        }
    }

}

#Preview {
    ContentView()
        .modelContainer(for: Vault.self, inMemory: true)
}
