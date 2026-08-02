import SwiftUI

struct FolderNameSheet: View {
    @Environment(\.dismiss)
    private var dismiss

    @State private var folderTitle: String

    let title: String
    let actionTitle: String
    let onSubmit: (String) -> Bool

    init(title: String, initialTitle: String, actionTitle: String, onSubmit: @escaping (String) -> Bool) {
        self.title = title
        self.actionTitle = actionTitle
        self.onSubmit = onSubmit
        _folderTitle = State(initialValue: initialTitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
            TextField("Folder Name", text: $folderTitle)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(actionTitle) {
                    if onSubmit(folderTitle) {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(folderTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
