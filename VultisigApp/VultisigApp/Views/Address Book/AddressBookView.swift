//
//  AddressBookView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-10.
//

import SwiftUI
import SwiftData

// Helper struct for safe decoding of CoinMeta
private struct AddressBookSafeCoinMeta: Decodable {
    let chain: String
}

struct AddressBookView: View {
    var shouldReturnAddress = true
    @Binding var returnAddress: String
    
    @Query var savedAddresses: [AddressBookItem]
    
    @State var title: String = ""
    @State var address: String = ""
    @State var isEditing = false
    @State var coin: Coin?
    
    @Environment(\.modelContext) var modelContext
    
    var body: some View {
        content
    }
    
    var view: some View {
        ZStack {
            if getValidAddresses().count == 0 {
                emptyView
            } else {
                // Platform-specific implementations define 'list'
                // This is a placeholder that should never be seen
                #if os(iOS) || os(macOS)
                list
                #else
                Text("Address list not available on this platform")
                #endif
            }
        }
    }
    
    // Helper to get valid addresses (chains that still exist)
    func getValidAddresses() -> [AddressBookItem] {
        savedAddresses.filter { item in
            do {
                // Check if we can create a Chain from the stored raw value
                let data = try JSONEncoder().encode(item.coinMeta)
                let safeMeta = try JSONDecoder().decode(AddressBookSafeCoinMeta.self, from: data)
                if Chain(rawValue: safeMeta.chain) != nil {
                    return true
                }
                return false
            } catch {
                print("Error filtering address book item '\(item.title)': \(error)")
                return false
            }
        }
    }
    
    var emptyView: some View {
        VStack {
            Spacer()
            ErrorMessage(text: "noSavedAddresses")
            Spacer()
        }
    }
    
    var emptyViewChain: some View {
        VStack {
            Spacer()
            ErrorMessage(text: "noSavedAddressesForChain")
            Spacer()
        }
    }
    
    var navigationButton: some View {
        Button {
            toggleEdit()
        } label: {
            navigationEditButton
        }
    }
    
    var navigationEditButton: some View {
        ZStack {
            if isEditing {
                doneButton
            } else {
                NavigationEditButton()
            }
        }
    }
    
    var doneButton: some View {
        Text(NSLocalizedString("done", comment: ""))
            .font(.body18MenloBold)
            .foregroundColor(.neutral0)
    }
    
    private func toggleEdit() {
        withAnimation {
            isEditing.toggle()
        }
    }
    
    func move(from: IndexSet, to: Int) {
        var s = savedAddresses.sorted(by: { $0.order < $1.order })
        s.move(fromOffsets: from, toOffset: to)
        for (index, item) in s.enumerated() {
                item.order = index
        }
        try? self.modelContext.save()
    }
    
    // Debug function (uncomment and call from .onAppear to debug address book items)
    /*
    func debugAddressBookItems() {
        print("=== DEBUG: Address Book Items ===")
        print("Total items in database: \(savedAddresses.count)")
        
        for (index, item) in savedAddresses.enumerated() {
            print("\n--- Item \(index + 1) ---")
            print("Order: \(item.order)")
            print("Title: \(item.title)")
            print("Address: \(item.address)")
            
            // Try to decode the coinMeta
            do {
                // Encode the coinMeta to see its raw data
                let encoder = JSONEncoder()
                let data = try encoder.encode(item.coinMeta)
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("CoinMeta JSON: \(jsonString)")
                }
                
                // Check if it's valid
                let decoder = JSONDecoder()
                if let safeMeta = try? decoder.decode(AddressBookSafeCoinMeta.self, from: data) {
                    print("Chain Raw Value: \(safeMeta.chain)")
                    
                    // Check if chain exists in current enum
                    if let _ = Chain(rawValue: safeMeta.chain) {
                        print("✅ Chain is VALID")
                    } else {
                        print("❌ Chain is INVALID (removed from app)")
                    }
                } else {
                    print("❌ Failed to decode safe metadata")
                }
                
            } catch {
                print("❌ Error processing item: \(error)")
            }
        }
        
        print("\n=== Valid Addresses ===")
        let validAddresses = getValidAddresses()
        print("Valid addresses count: \(validAddresses.count)")
        for item in validAddresses {
            print("- \(item.title): \(item.coinMeta.ticker)")
        }
        
        print("\n=== End Debug ===")
    }
    */
    
}

#Preview {
    AddressBookView(returnAddress: .constant(""), coin: Coin.example)
        .environmentObject(CoinSelectionViewModel())
        .environmentObject(HomeViewModel())
}
