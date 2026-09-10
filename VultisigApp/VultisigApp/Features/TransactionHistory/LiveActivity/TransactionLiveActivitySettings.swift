#if DEBUG && os(iOS)
import SwiftUI

struct TransactionLiveActivitySettings: View {
    @AppStorage(TransactionActivityPolicy.enabledKey) private var enabled = false
    @AppStorage(TransactionActivityPolicy.detailsKey) private var details = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("transactionActivitySetting".localized)
                Spacer()
                VultiToggle(isOn: $enabled)
            }
            HStack {
                Text("transactionActivityDetails".localized)
                Spacer()
                VultiToggle(isOn: $details)
            }
            .disabled(!enabled)
            Text("transactionActivityPrototype".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
            PrimaryButton(title: "transactionActivityFixture") {
                TransactionLiveActivityDemo.shared.run()
            }
        }
        .font(Theme.fonts.bodyMMedium)
        .foregroundStyle(Theme.colors.textPrimary)
        .onChange(of: enabled) { _, _ in TransactionLiveActivityCoordinator.shared.refresh() }
        .onChange(of: details) { _, _ in TransactionLiveActivityCoordinator.shared.refresh() }
    }
}
#endif
