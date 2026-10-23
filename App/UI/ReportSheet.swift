import SwiftUI

/// Prepares a GitHub issue: a description, optionally with the saved crash reports. The user
/// reviews it on GitHub before anything is sent.
struct ReportSheet: View {
    @Binding var description: String
    @Binding var includeCrashReports: Bool
    let crashReportCount: Int
    var onCancel: () -> Void = {}
    var onOpenIssue: () -> Void = {}
    var onDeleteCrashReports: () -> Void = {}
    @Environment(\.isSnapshotRendering) private var isSnapshotRendering

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "report-title", defaultValue: "Send a report"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Text(String(localized: "report-body",
                        defaultValue: "Describe what happened. Keyline opens a new issue on GitHub with your description, the Keyline and macOS versions and, if you choose, crash details. You review it there before sending. Reports never include access keys or server addresses."))
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            descriptionField
            if crashReportCount > 0 {
                Toggle(isOn: $includeCrashReports) {
                    Text(String(localized: "report-include-crashes",
                                defaultValue: "Include crash details (\(crashReportCount) saved)"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                }
                .toggleStyle(KeylineToggleStyle())
            }
            HStack {
                if crashReportCount > 0 {
                    Button(String(localized: "report-delete-crashes", defaultValue: "Delete crash details"), action: onDeleteCrashReports)
                        .buttonStyle(KeylineButtonStyle(kind: .destructive))
                }
                Spacer()
                Button(String(localized: "cancel", defaultValue: "Cancel"), action: onCancel)
                    .buttonStyle(KeylineButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "report-open-github", defaultValue: "Open on GitHub"), action: onOpenIssue)
                    .buttonStyle(KeylineButtonStyle(kind: .primary))
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Theme.background)
    }

    @ViewBuilder private var descriptionField: some View {
        Group {
            if isSnapshotRendering {
                Text(description.isEmpty ? " " : description)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                TextEditor(text: $description)
            }
        }
        .font(.system(size: 13))
        .foregroundColor(Theme.textPrimary)
        .frame(height: 110)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.surfaceStroke))
    }
}
