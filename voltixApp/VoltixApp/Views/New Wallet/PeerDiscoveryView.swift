//
//  PeerDiscoveryView.swift
//  VoltixApp
//

import SwiftUI

struct PeerDiscoveryView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @State private var peersFound = [String]() //TODO: Make this a list of peer types
    @State private var selections = Set<String>()
    
    var body: some View {
        VStack {
            Text("p2p discovery")
            List(peersFound, id: \.self, selection: $selections) { peer in
                HStack {
                    if selections.contains(peer) {
                        Image(systemName: "checkmark.circle")
                    } else {
                        Image(systemName: "circle")
                    }
                    Text(peer)
                }
                .onTapGesture {
                    if selections.contains(peer) {
                        selections.remove(peer)
                    } else {
                        selections.insert(peer)
                    }
                }
            }
            Button("Create Wallet >") {
                Task {
                    // TODO: TSS Keygen
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    presentationStack.append(.finishedTSSKeygen)
                }
            }
            .disabled(selections.count != 2)
        }
        .task {
            // TODO: Initiate peer discovery and return results via an AsyncSequence
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                peersFound.append("iPad Pro")
                try await Task.sleep(nanoseconds: 1_000_000_000)
                peersFound.append("iPhone 15")
            } catch {}
        }
    }
}

#Preview {
    PeerDiscoveryView(presentationStack: .constant([]))
}
