import SwiftUI
import UIKit

/// 添加端点：网关地址 + 6 位配对码 → `POST /__mobile/api/pair`，令牌写入钥匙串。
struct AddEndpointView: View {

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var address = ""
    @State private var code = ""
    @State private var isPairing = false
    @State private var isTesting = false
    @State private var errorMessage: String?
    @State private var testMessage: String?
    @State private var testSucceeded = false

    private var canSubmit: Bool {
        Endpoint.normalizedURL(address) != nil && AppModel.isValidPairCode(code)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(t("add.name.placeholder"), text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    TextField(t("add.address.placeholder"), text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        pasteAddress()
                    } label: {
                        Label(t("add.paste"), systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text(t("add.section.endpoint"))
                } footer: {
                    Text(t("add.address.footnote"))
                }

                Section {
                    TextField(t("add.code.placeholder"), text: $code)
                        .keyboardType(.numberPad)
                        .onChange(of: code) { newValue in
                            let digits = String(newValue.filter { $0.isNumber }.prefix(6))
                            if digits != newValue {
                                code = digits
                            }
                        }
                } header: {
                    Text(t("add.code"))
                } footer: {
                    Text(t("add.codeHint"))
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack(spacing: 8) {
                            if isTesting {
                                ProgressView()
                            } else {
                                Image(systemName: "network")
                            }
                            Text(t("add.test"))
                        }
                    }
                    .disabled(isTesting || Endpoint.normalizedURL(address) == nil)

                    if let testMessage = testMessage {
                        Text(testMessage)
                            .font(.footnote)
                            .foregroundColor(testSucceeded ? .green : .red)
                    }
                }

                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button {
                        Task { await pair() }
                    } label: {
                        HStack {
                            Spacer()
                            if isPairing {
                                ProgressView()
                                    .padding(.trailing, 6)
                            }
                            Text(isPairing ? t("add.pairing") : t("add.pair"))
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit || isPairing)
                } footer: {
                    Text(t("add.deeplinkHint"))
                }
            }
            .navigationTitle(t("add.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.cancel")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    name = settings.deviceName
                }
            }
        }
    }

    @MainActor
    private func pair() async {
        guard canSubmit, !isPairing else { return }
        isPairing = true
        errorMessage = nil
        defer { isPairing = false }
        do {
            _ = try await app.pair(name: name, rawURL: address, code: code)
            dismiss()
            await app.status.refreshAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func testConnection() async {
        guard let baseURL = Endpoint.normalizedURL(address) else {
            testSucceeded = false
            testMessage = t("add.error.addressInvalid")
            return
        }
        isTesting = true
        defer { isTesting = false }
        do {
            let health = try await StatusClient.health(baseURL: baseURL)
            testSucceeded = true
            testMessage = String(format: t("add.test.ok"), health.summary)
        } catch {
            testSucceeded = false
            testMessage = error.localizedDescription
        }
    }

    private func pasteAddress() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        address = text
    }
}
