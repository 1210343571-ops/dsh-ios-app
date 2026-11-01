import SwiftUI

/// 设置：Face ID 锁、刷新间隔、语言、设备名、外观、关于与清空数据。
struct SettingsView: View {

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var endpoints: EndpointStore
    @EnvironmentObject private var settings: SettingsStore

    @State private var showingClear = false

    var body: some View {
        NavigationStack {
            Form {
                securitySection
                dataSection
                appearanceSection
                aboutSection
                dangerSection
            }
            .navigationTitle(t("settings.title"))
            .confirmationDialog(t("settings.clear"),
                                isPresented: $showingClear,
                                titleVisibility: .visible) {
                Button(t("settings.clear.confirm"), role: .destructive) {
                    app.clearAllData()
                }
                Button(t("common.cancel"), role: .cancel) {}
            } message: {
                Text(t("settings.clear.message"))
            }
        }
    }

    private var securitySection: some View {
        Section {
            Toggle(isOn: biometricBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("settings.biometric"))
                    Text(app.biometry.kind.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .disabled(!app.biometry.available)

            if !app.biometry.available {
                Text(t("settings.biometric.unavailable"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if settings.biometricLockEnabled && app.biometry.available {
                Button {
                    app.lockNow()
                } label: {
                    Label(t("settings.lockNow"), systemImage: "lock.fill")
                }
            }
        } header: {
            Text(t("settings.section.security"))
        } footer: {
            Text(t("settings.biometric.footnote"))
        }
    }

    private var dataSection: some View {
        Section {
            Picker(t("settings.poll"), selection: pollBinding) {
                ForEach(SettingsStore.pollOptions, id: \.self) { seconds in
                    Text(String(format: t("settings.poll.seconds"), seconds)).tag(seconds)
                }
            }

            Picker(t("settings.language"), selection: languageBinding) {
                Text(t("settings.language.system")).tag("system")
                Text(t("settings.language.zh")).tag("zh-Hans")
                Text(t("settings.language.en")).tag("en")
            }

            TextField(t("settings.deviceName"), text: deviceNameBinding)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        } header: {
            Text(t("settings.section.data"))
        } footer: {
            Text(t("settings.deviceName.footnote"))
        }
    }

    private var appearanceSection: some View {
        Section {
            InfoRow(title: t("settings.section.appearance"), value: t("settings.appearance.followSystem"))
        } footer: {
            Text(t("settings.appearance.footnote"))
        }
    }

    private var aboutSection: some View {
        Section {
            InfoRow(title: t("settings.version"), value: UpdateChecker.appVersionDisplay)
            InfoRow(title: t("settings.endpoints.count"), value: String(endpoints.count))

            TextField(t("update.app.storeId"), text: appStoreIDBinding)
                .keyboardType(.numberPad)
        } header: {
            Text(t("settings.section.about"))
        } footer: {
            Text(t("settings.consoleHint"))
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showingClear = true
            } label: {
                Label(t("settings.clear"), systemImage: "trash")
            }
        }
    }

    private var biometricBinding: Binding<Bool> {
        Binding(get: { settings.biometricLockEnabled },
                set: { newValue in
                    settings.biometricLockEnabled = newValue
                    app.settingsDidChange()
                })
    }

    private var pollBinding: Binding<Int> {
        Binding(get: { settings.pollSeconds },
                set: { newValue in
                    settings.pollSeconds = newValue
                    app.settingsDidChange()
                })
    }

    private var languageBinding: Binding<String> {
        Binding(get: { settings.language },
                set: { newValue in
                    settings.language = newValue
                })
    }

    private var deviceNameBinding: Binding<String> {
        Binding(get: { settings.deviceName },
                set: { newValue in
                    settings.deviceName = newValue
                })
    }

    private var appStoreIDBinding: Binding<String> {
        Binding(get: { settings.appStoreID },
                set: { newValue in
                    settings.appStoreID = newValue
                })
    }
}
