import SwiftUI

struct AddLinkView: View {
    @Environment(ItemStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    private var url: URL? {
        LinkCleaner.firstURL(in: text)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Paste a link from any music app or website.")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)

                TextField("https://…", text: $text, axis: .vertical)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($fieldFocused)
                    .padding(14)
                    .foregroundStyle(theme.text)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack {
                    PasteButton(payloadType: URL.self) { urls in
                        if let first = urls.first { text = first.absoluteString }
                    }
                    .buttonBorderShape(.capsule)
                    .labelStyle(.titleAndIcon)
                    Spacer()
                }

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }

                Spacer()

                Button(action: save) {
                    HStack {
                        if isSaving { ProgressView().tint(theme.onAccent) }
                        Text(isSaving ? "Saving…" : "Save to Queue")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(theme.onAccent)
                    .background(theme.accent.opacity(url == nil ? 0.4 : 1), in: Capsule())
                }
                .disabled(url == nil || isSaving)
            }
            .padding(20)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Add Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { fieldFocused = true }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let url else { return }
        isSaving = true
        errorMessage = nil
        Task {
            _ = await LibrarySaver.save(url)
            store.reload()
            isSaving = false
            dismiss()
        }
    }
}
