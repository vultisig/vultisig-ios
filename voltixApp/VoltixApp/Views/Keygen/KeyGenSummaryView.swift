//
//  KeyGenSummaryView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-11.
//

import SwiftUI

struct KeyGenSummaryView: View {
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationTitle(NSLocalizedString("summary", comment: "Summary"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                devicesList
            }
            .padding(.top, 30)
            .foregroundColor(.neutral0)
        }
    }
    
    var header: some View {
        VStack(spacing: 12) {
            title
            numberOfDevices
        }
    }
    
    var devicesList: some View {
        VStack(spacing: 16) {
            devicesListTitle
            list
        }
    }
    
    var title: some View {
        Text(NSLocalizedString("youAreCreatingA", comment: "You are creating a"))
            .font(.body12MontserratSemiBold)
    }
    
    var numberOfDevices: some View {
        Group {
            Text("2 ") +
            Text(NSLocalizedString("of", comment: "of")) +
            Text(" 3 ") +
            Text(NSLocalizedString("vaults", comment: "vaults"))
        }
        .font(.body20MontserratSemiBold)
    }
    
    var devicesListTitle: some View {
        Text(NSLocalizedString("withTheseDevices", comment: "With these devices"))
            .font(.body12MontserratSemiBold)
    }
    
    var list: some View {
        VStack {
            
        }
    }
}

#Preview {
    KeyGenSummaryView()
}
