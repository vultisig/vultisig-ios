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
        Group {
            if viewModel.hasResponse {
                scanResultView
            } else if viewModel.isScanning {
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

// MARK: - Compact Security Scan View

struct CompactSecurityScanView: View {
    @ObservedObject var viewModel: SecurityScanViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.iconName)
                .foregroundColor(viewModel.iconColor)
                .font(.system(size: 14, weight: .medium))
            
            if viewModel.isScanning {
                Text("Scanning...")
                    .foregroundColor(.neutral200)
                    .font(.body10MontserratSemiBold)
            } else if viewModel.hasResponse {
                Text(viewModel.isSecure ? "Verified" : "\(viewModel.warningMessages.count) warnings")
                    .foregroundColor(.neutral0)
                    .font(.body10MontserratSemiBold)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(viewModel.backgroundColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(viewModel.borderColor, lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Completely secure transaction
        SecurityScanView(viewModel: {
            let vm = SecurityScanViewModel()
            vm.scanResponse = SecurityScanResponse(
                provider: "Blockaid",
                isSecure: true,
                riskLevel: .none,
                warnings: [],
                recommendations: [],
                metadata: nil
            )
            return vm
        }())
        
        // Risky transaction
        SecurityScanView(viewModel: {
            let vm = SecurityScanViewModel()
            vm.scanResponse = SecurityScanResponse(
                provider: "Blockaid",
                isSecure: false,
                riskLevel: .high,
                warnings: [
                    SecurityWarning(
                        type: .suspiciousContract,
                        severity: .error,
                        message: "This contract has been flagged as potentially malicious",
                        details: "0x1234567890123456789012345678901234567890"
                    ),
                    SecurityWarning(
                        type: .highValueTransfer,
                        severity: .warning,
                        message: "This is a high-value transaction",
                        details: nil
                    )
                ],
                recommendations: [
                    "Double-check the recipient address",
                    "Consider using a smaller test amount first"
                ],
                metadata: nil
            )
            return vm
        }())
        
        // Scanning state
        SecurityScanView(viewModel: {
            let vm = SecurityScanViewModel()
            vm.isScanning = true
            return vm
        }())
    }
    .padding()
                    .background(Color.blue800)
} 