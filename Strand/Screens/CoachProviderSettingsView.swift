import SwiftUI
import StrandDesign

/// Drafts keep edits local until Save; opening or cancelling never disconnects the provider.
struct CoachProviderSettingsView: View {
    @ObservedObject var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss
    @State private var baseURL: String
    @State private var authHeader: CustomAIAuthHeader
    @State private var model: String
    @State private var replacementKey = ""
    @State private var removeKey = false
    @State private var saveError: String?

    init(coach: AICoachEngine) {
        self.coach = coach
        _baseURL = State(initialValue: coach.customBaseURL)
        _authHeader = State(initialValue: coach.customAuthHeader)
        _model = State(initialValue: coach.model)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    Text(coach.provider.displayName)
                }
                if coach.provider == .custom {
                    Section {
                        TextField("Server URL", text: $baseURL)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                            .accessibilityIdentifier("coach.settings.url")
                        Picker("Key header", selection: $authHeader) {
                            ForEach(CustomAIAuthHeader.allCases) { header in
                                Text(header.displayName).tag(header)
                            }
                        }
                    } header: {
                        Text("Connection")
                    } footer: {
                        Text("HTTP and HTTPS endpoints are supported. Include the API base path, such as /v1, if your server requires it.")
                    }
                }
                Section("Model") {
                    TextField("Model ID", text: $model)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .accessibilityIdentifier("coach.settings.model")
                    if !coach.availableModels.isEmpty {
                        Menu("Choose a model") {
                            ForEach(coach.availableModels.filter { !$0.isEmpty }, id: \.self) { id in
                                Button(id) { model = id }
                            }
                        }
                    }
                }
                Section {
                    SecureField(coach.hasProviderKey ? "Leave blank to keep the saved key" : "API key", text: $replacementKey)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .accessibilityLabel("API key")
                    if coach.provider == .custom && coach.hasProviderKey {
                        Toggle("Remove saved key", isOn: $removeKey)
                            .disabled(!replacementKey.isEmpty)
                    }
                } header: {
                    Text(coach.provider == .custom ? "API key (optional)" : "API key")
                } footer: {
                    Text("Changes take effect when you save. Your conversation is kept.")
                }
                if let saveError {
                    Section {
                        Text(saveError).foregroundStyle(StrandPalette.metricRose)
                    }
                }
                Section {
                    Button("Disconnect provider", role: .destructive) {
                        coach.disconnect()
                        dismiss()
                    }
                    .disabled(coach.sending)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Provider settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if coach.saveProviderSettings(baseURL: baseURL, authHeader: authHeader,
                                                      model: model, replacementKey: replacementKey,
                                                      removeKey: removeKey) {
                            dismiss()
                        } else {
                            saveError = coach.errorText
                        }
                    }
                    .disabled(coach.sending || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 520)
        #endif
    }
}
