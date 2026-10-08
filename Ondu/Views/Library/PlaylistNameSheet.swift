import SwiftUI

/// Reused by Create and Rename — a single text field with Save/Cancel.
struct PlaylistNameSheet: View {
    enum Mode {
        case create
        case createFolder
        case rename(initialName: String)
    }

    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    let onSave: (String) async -> Void

    @State private var name: String = ""
    @State private var isSaving: Bool = false
    @FocusState private var focused: Bool

    private var title: String {
        switch mode {
        case .create: "New Playlist"
        case .createFolder: "New Folder"
        case .rename: "Rename"
        }
    }

    private var saveLabel: String {
        switch mode {
        case .create, .createFolder: "Create"
        case .rename: "Save"
        }
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .disabled(isSaving)
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveLabel, action: save)
                        .disabled(trimmed.isEmpty || isSaving)
                }
            }
        }
        .onAppear {
            if case .rename(let initial) = mode, name.isEmpty {
                name = initial
            }
            focused = true
        }
    }

    private func save() {
        guard !trimmed.isEmpty, !isSaving else { return }
        isSaving = true
        Task {
            await onSave(trimmed)
            dismiss()
        }
    }
}
