//
//  ReferredOnboardingGuideAnimation.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-27.
//

import SwiftUI

struct ReferredOnboardingGuideAnimation: View {
    @State var contentHeight: CGFloat = .zero
    @State var cellHeight: CGFloat = .zero
    
    @State var showCell1: Bool = false
    @State var showCell2: Bool = false
    @State var showCell3: Bool = false
    @State var showCell4: Bool = false
    
    var body: some View {
        HStack(spacing: 0) {
            rectangle
            content
        }
        .padding(24)
    }
    
    var rectangle: some View {
        Rectangle()
            .frame(width: 2, height: contentHeight-cellHeight+6)
            .foregroundColor(.blue600)
            .offset(y: -2)
    }

    var content: some View {
        VStack(spacing: 28) {
            headerContent
            title
            list
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        contentHeight = geometry.size.height
                        setData()
                    }
            }
        )
    }

    var headerContent: some View {
        HStack {
            header
            Spacer()
        }
    }

    var header: some View {
        HStack {
            icon
            text
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(32)
        .overlay(
            RoundedRectangle(cornerRadius: 32)
                .stroke(Color.blue200, lineWidth: 1)
        )
        .offset(x: -2)
    }

    var icon: some View {
        Image(systemName: "horn")
            .foregroundColor(.infoBlue)
    }

    var text: some View {
        Text(NSLocalizedString("referralProgram", comment: ""))
            .foregroundColor(.extraLightGray)
            .font(.body12BrockmannMedium)
    }

    var title: some View {
        Text(NSLocalizedString("howItWorks", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body34BrockmannMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 24)
    }
    
    var shadow: some View {
        Circle()
            .frame(width: 360, height: 360)
            .foregroundColor(.alertTurquoise)
            .opacity(0.05)
            .blur(radius: 20)
    }

    var list: some View {
        VStack(spacing: 16) {
            getCell(
                icon: "dots.and.line.vertical.and.cursorarrow.rectangle",
                title: "referralOnboardingTitle1",
                description: "referralOnboardingDescription1",
                showCell: showCell1
            )
            
            getCell(
                icon: "shareplay",
                title: "referralOnboardingTitle2",
                description: "referralOnboardingDescription2",
                showCell: showCell2
            )
            
            getCell(
                icon: "trophy",
                title: "referralOnboardingTitle3",
                description: "referralOnboardingDescription3",
                showCell: showCell3
            )
            
            getCell(
                icon: "person.badge.shield.checkmark",
                title: "referralOnboardingTitle4",
                description: "referralOnboardingDescription4",
                showCell: showCell4
            )
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            cellHeight = geometry.size.height
                        }
                }
            )
        }
    }

    private func getCell(
        icon: String,
        title: String,
        description: String,
        showCell: Bool
    ) -> some View {
        HStack(spacing: 0){
            Rectangle()
                .frame(width: 22, height: 2)
                .foregroundColor(.blue600)

            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.persianBlue200)
                    .font(.body20MontserratMedium)

                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString(title, comment: ""))
                        .font(.body14BrockmannMedium)
                    
                    Text(NSLocalizedString(description, comment: ""))
                        .font(.body10BrockmannMedium)
                }
                .foregroundColor(.neutral0)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(Color.blue600)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue200, lineWidth: 1)
            )
        }
        .opacity(showCell ? 1 : 0)
        .offset(y: showCell ? 0 : -10)
        .animation(.easeInOut, value: showCell)
    }
    
    private func setData() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showCell1 = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showCell2 = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showCell3 = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showCell4 = true
        }
    }
}

#Preview {
    ReferredOnboardingGuideAnimation()
}
