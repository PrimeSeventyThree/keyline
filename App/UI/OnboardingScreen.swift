import SwiftUI

/// The first-run screens: a privacy note, installing the VPN component, and adding a server.
struct OnboardingScreen: View {
    enum Step: Int, CaseIterable {
        case welcome, vpnComponent, addServer
    }

    let step: Step
    let extensionState: SystemExtensionManager.State
    @Binding var accessKey: String
    var addServerError: String?
    var onContinue: () -> Void = {}
    var onBack: () -> Void = {}
    var onInstall: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onAddServer: () -> Void = {}
    var onSkip: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 18) {
                stepContent
            }
            .padding(32)
            .frame(width: 560, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.25)))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.surfaceStroke))
            progressDots.padding(.top, 20)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .welcome: welcome
        case .vpnComponent: vpnComponent
        case .addServer: addServer
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        Group {
            Image("KeylineMark", bundle: .keylineResources)
                .resizable()
                .renderingMode(.template)
                .foregroundColor(Color.black.opacity(0.85))
                .frame(width: 34, height: 34)
                .padding(11)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent))
                .shadow(color: Theme.accent.opacity(0.5), radius: 14)
            title(String(localized: "onboarding-welcome-title", defaultValue: "Welcome to Keyline"))
            paragraph(String(localized: "onboarding-welcome-body",
                        defaultValue: "Keyline connects you to your own server with an Outline access key, so your traffic goes through a server you trust."))
            VStack(alignment: .leading, spacing: 10) {
                point("key", String(localized: "onboarding-privacy-keys",
                                    defaultValue: "Access keys stay on this Mac, in your Keychain."))
                point("eye.slash", String(localized: "onboarding-privacy-no-tracking",
                                          defaultValue: "Keyline has no accounts, ads or tracking. It never sends your browsing anywhere but your server."))
                point("globe", String(localized: "onboarding-privacy-countries",
                                      defaultValue: "Server countries are looked up offline, on this Mac."))
                point("shield.lefthalf.filled", String(localized: "onboarding-privacy-provider",
                                                      defaultValue: "Whoever runs your server can see the sites you visit, as with any VPN. Only use servers you trust."))
            }
            .padding(.top, 4)
            HStack {
                Spacer()
                Button(String(localized: "onboarding-understand", defaultValue: "I understand"), action: onContinue)
                    .buttonStyle(KeylineButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
    }

    private var vpnComponent: some View {
        Group {
            title(String(localized: "onboarding-component-title", defaultValue: "Install the VPN component"))
            paragraph(String(localized: "onboarding-component-body",
                        defaultValue: "Keyline routes your traffic with a network extension. macOS asks you to allow it once."))
            componentStatus
            if extensionState == .needsApproval {
                VStack(alignment: .leading, spacing: 8) {
                    numbered(1, String(localized: "onboarding-approve-step-1", defaultValue: "Click Open System Settings."))
                    numbered(2, String(localized: "onboarding-approve-step-2",
                                       defaultValue: "Go to \(SystemExtensionManager.approvalLocation)."))
                    numbered(3, String(localized: "onboarding-approve-step-3",
                                       defaultValue: "Turn on Keyline Tunnel, and enter your password if asked."))
                }
            }
            paragraph(String(localized: "onboarding-component-vpn-prompt",
                        defaultValue: "When you first connect, macOS also asks to add a VPN configuration. Choose Allow."))
                .font(.system(size: 12))
            HStack {
                Button(String(localized: "back", defaultValue: "Back"), action: onBack)
                    .buttonStyle(KeylineButtonStyle())
                Spacer()
                switch extensionState {
                case .needsApproval:
                    Button(String(localized: "open-system-settings", defaultValue: "Open System Settings"), action: onOpenSettings)
                        .buttonStyle(KeylineButtonStyle(kind: .primary))
                case .failed, .unknown:
                    Button(String(localized: "onboarding-install", defaultValue: "Install"), action: onInstall)
                        .buttonStyle(KeylineButtonStyle(kind: .primary))
                case .activated:
                    Button(String(localized: "continue", defaultValue: "Continue"), action: onContinue)
                        .buttonStyle(KeylineButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                case .activating, .notInApplications:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder private var componentStatus: some View {
        let (icon, color, text): (String, Color, String) = {
            switch extensionState {
            case .activated:
                return ("checkmark.circle.fill", Theme.accent,
                        String(localized: "vpn-component-installed", defaultValue: "Installed and allowed"))
            case .activating, .unknown:
                return ("clock", Theme.textSecondary, String(localized: "onboarding-component-installing", defaultValue: "Installing…"))
            case .needsApproval:
                return ("exclamationmark.circle.fill", Theme.warning,
                        String(localized: "vpn-component-needs-approval", defaultValue: "Waiting for your approval in System Settings"))
            case .notInApplications:
                return ("folder.badge.questionmark", Theme.warning,
                        String(localized: "setup-move-to-applications",
                               defaultValue: "Move Keyline to the Applications folder, then open it again."))
            case .failed(let reason):
                return ("xmark.octagon.fill", Theme.danger,
                        String(localized: "setup-failed", defaultValue: "The VPN component couldn’t be installed: \(reason)"))
            }
        }()
        Label {
            Text(text).foregroundColor(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundColor(color)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.10)))
    }

    private var addServer: some View {
        Group {
            title(String(localized: "onboarding-server-title", defaultValue: "Add your first server"))
            paragraph(String(localized: "add-server-body",
                        defaultValue: "Paste the access key from your provider. Keys stay on this Mac, in your Keychain."))
            AccessKeyField(accessKey: $accessKey, isInvalid: addServerError != nil)
            if let addServerError {
                Text(addServerError).font(.system(size: 12)).foregroundColor(Theme.danger)
            }
            HStack {
                Button(String(localized: "back", defaultValue: "Back"), action: onBack)
                    .buttonStyle(KeylineButtonStyle())
                Spacer()
                Button(String(localized: "onboarding-skip", defaultValue: "Skip for now"), action: onSkip)
                    .buttonStyle(KeylineButtonStyle())
                Button(String(localized: "add", defaultValue: "Add"), action: onAddServer)
                    .buttonStyle(KeylineButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(accessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Pieces

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.self) { item in
                Capsule()
                    .fill(item == step ? Theme.accent : Color.white.opacity(0.2))
                    .frame(width: item == step ? 22 : 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(String(localized: "onboarding-progress",
                                        defaultValue: "Step \(step.rawValue + 1) of \(Step.allCases.count)")))
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 24, weight: .bold)).foregroundColor(Theme.textPrimary)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text).font(.system(size: 14)).foregroundColor(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).foregroundColor(Theme.accent).frame(width: 18)
            Text(text).font(.system(size: 13)).foregroundColor(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func numbered(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color.black.opacity(0.85))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Theme.accent))
            Text(text).font(.system(size: 13)).foregroundColor(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The access key text field, shared by the Add server sheet and onboarding.
struct AccessKeyField: View {
    @Binding var accessKey: String
    var isInvalid = false

    var body: some View {
        ThemedTextField(placeholder: "ss://… or ssconf://…", text: $accessKey, isInvalid: isInvalid, monospaced: true)
    }
}
