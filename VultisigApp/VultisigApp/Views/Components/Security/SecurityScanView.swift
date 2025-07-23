//
//  SecurityScanView.swift
//  VultisigApp
//
//  Created by Assistant on 2025-01-14.
//

import SwiftUI

struct SecurityScanView: View {
    @ObservedObject var viewModel: SecurityScanViewModel
    @State private var isExpanded = false
    
    var body: some View {
        ZStack {
            // TODO: - Add UI for bottom sheet
            if viewModel.isScanning {
                scanningView
            }
        }
        .alert(isPresented: $viewModel.showAlert) {
            viewModel.scanErrorAlert
        }
    }
    
    private var scanResultView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                icon
                mainContent
                Spacer()
                if viewModel.hasWarnings {
                    expandButton
                }
            }
            
            if isExpanded {
                expandedContent
            }
        }
        .padding(12)
        .background(viewModel.backgroundColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(viewModel.borderColor, lineWidth: lineWidth)
        )
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
    
    private var scanningView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            
            Text("Scanning transaction for security issues...")
                .foregroundColor(.neutral0)
                .font(.body12MontserratSemiBold)
        }
        .padding(12)
        .background(Color.blue600.opacity(0.3))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue600, lineWidth: lineWidth)
        )
    }
    
    private var icon: some View {
        Image(systemName: viewModel.iconName)
            .foregroundColor(viewModel.iconColor)
            .font(.system(size: 16, weight: .medium))
    }
    
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.getScanSummary())
                .foregroundColor(.neutral0)
                .font(.body12MontserratSemiBold)
                .multilineTextAlignment(.leading)
            
            if !viewModel.isScanning {
                providerLabel
            }
        }
    }
    
    private var providerLabel: some View {
        Text("Scanned by \(viewModel.providerName)")
            .foregroundColor(.neutral200)
            .font(.body10MontserratSemiBold)
    }
    
    private var expandButton: some View {
        Button(action: {
            withAnimation {
                isExpanded.toggle()
            }
        }) {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .foregroundColor(.neutral0)
                .font(.system(size: 12, weight: .medium))
        }
    }
    
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.warningMessages.isEmpty {
                warningsSection
            }
            
            if !viewModel.recommendations.isEmpty {
                recommendationsSection
            }
        }
    }
    
    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Security Warnings:")
                .foregroundColor(.neutral0)
                .font(.body12MontserratBold)
            
            ForEach(viewModel.warningMessages, id: \.self) { warning in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 10))
                        .padding(.top, 2)
                    
                    Text(warning)
                        .foregroundColor(.neutral0)
                        .font(.body10MontserratSemiBold)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }
    
    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recommendations:")
                .foregroundColor(.neutral0)
                .font(.body12MontserratBold)
            
            ForEach(viewModel.recommendations, id: \.self) { recommendation in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 10))
                        .padding(.top, 2)
                    
                    Text(recommendation)
                        .foregroundColor(.neutral0)
                        .font(.body10MontserratSemiBold)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }
    
    private var lineWidth: CGFloat {
#if os(iOS)
        return 1
#else
        return 2
#endif
    }
}

// MARK: - Risk Level Badge

struct SecurityRiskBadge: View {
    let riskLevel: SecurityRiskLevel
    
    var body: some View {
        Text(riskLevel.displayName.uppercased())
            .font(.body10MontserratSemiBold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor)
            .cornerRadius(4)
    }
    
    private var badgeColor: Color {
        switch riskLevel {
        case .none:
            return .green
        case .low:
            return .green
        case .medium:
            return .yellow
        case .high:
            return .orange
        case .critical:
            return .red
        }
    }
}
