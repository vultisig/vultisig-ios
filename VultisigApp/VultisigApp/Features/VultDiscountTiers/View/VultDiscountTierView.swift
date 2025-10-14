//
//  VultDiscountTierView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/10/2025.
//

import SwiftUI

struct VultDiscountTierView: View {
    let tier: VultDiscountTier
    let vultToken: Coin?
    let isActive: Bool
    let canUnlock: Bool
    var onExpand: () -> Void
    var onUnlock: () -> Void
    
    @State var isExpanded: Bool = false
    @State var isActiveInternal: Bool = false
    
    var holdAmountText: String {
        let stringValue = "\(tier.balanceToUnlock.formatForDisplay()) $VULT"
    
        // No price for now
        // return [stringValue, fiatText].compactMap { $0 }.joined(separator: " ")
        return stringValue
    }
    
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                HStack(spacing: 12) {
                    VultDiscountTierIcon(tier: tier, size: 40)
                    Text(tier.name.localized)
                        .font(Theme.fonts.title1)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                
                Spacer()
                
                discountBadge
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.interpolatingSpring) {
                    isExpanded.toggle()
                    if isExpanded {
                        onExpand()
                    }
                }
            }
                        
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("hold".localized)
                        .font(Theme.fonts.footnote)
                        .foregroundStyle(Theme.colors.textExtraLight)
                    HStack {
                        Text(holdAmountText)
                            .font(Theme.fonts.priceBodyS)
                            .foregroundStyle(Theme.colors.textPrimary)
                        Spacer()
                        activeView
                            .transition(.opacity)
                            .showIf(isActiveInternal)
                    }
                }
                
                PrimaryButton(
                    title: "unlockTier".localized,
                    type: .secondary,
                    action: onUnlock
                )
                .transition(.opacity)
                .showIf(canUnlock)
            }
            .transition(.verticalGrowAndFade)
            .showIf(isExpanded)
        }
        .padding(16)
        .background(backgroundView.overlay(overlayView))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onLoad { animate(isActive: isActive) }
        .onChange(of: isActive) { _, newValue in
            animate(isActive: newValue)
        }
    }
    
    var backgroundView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.colors.bgSecondary)
            
            // Inner shadow with gradient
            gradientView
                .opacity(0.35)
                .mask(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(lineWidth: 8)
                        .blur(radius: 2)
                )
                .transition(.opacity)
                .showIf(isExpanded)
        }
    }
    
    var overlayView: some View {
        gradientView
            .opacity(0.5)
            .mask(RoundedRectangle(cornerRadius: 16)
                .inset(by: 1)
                .stroke(lineWidth: 1))
    }
    
    var discountBadge: some View {
        Text(String(format: "vultDiscount".localized, tier.bpsDiscount))
            .font(Theme.fonts.footnote)
            .foregroundStyle(Theme.colors.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.colors.bgTertiary))
            .overlay(Capsule().stroke(Theme.colors.border, lineWidth: 1))
            .fixedSize(horizontal: true, vertical: true)
    }
    
    var activeView: some View {
        HStack(spacing: 4) {
            Icon(named: "check", color: Theme.colors.alertSuccess, size: 10)
                .padding(4)
                .overlay(Circle().stroke(Theme.colors.alertSuccess))
            Text("active".localized)
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.alertSuccess)
        }
    }
    
    @ViewBuilder
    var gradientView: some View {
        LinearGradient(
            colors: [
                tier.primaryColor,
                tier.secondaryColor
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    func animate(isActive: Bool) {
        withAnimation(.interpolatingSpring) {
            isActiveInternal = isActive
            
            if isActive {
                isExpanded = true
            }
        }
    }
}

private extension VultDiscountTierView {
    var fiatText: String? {
        guard let vultToken else {
            return nil
        }
        
        let rate = RateProvider.shared.rate(for: vultToken)
        // If rate == 0, we default to 1 for displaying purposes till provider returns $VULT
        let rateToUse: Rate = (rate == nil || rate?.value == 0) ? Rate.identity : (rate ?? .identity)
        let fiatValue: String = RateProvider.shared.fiatBalanceString(value: tier.balanceToUnlock, coin: vultToken, rate: rateToUse)
        return "(~\(fiatValue))"
    }
}
