import SwiftUI

struct NewsEditorPlaceholderView: View {
    var body: some View {
        Form {
            Section {
                TextField("Title", text: .constant(""))
                    .disabled(true)
                TextField("Summary", text: .constant(""))
                    .disabled(true)
                TextField("Body", text: .constant(""))
                    .disabled(true)
                TextField("Image URL", text: .constant(""))
                    .disabled(true)
            }

            Section {
                Button("Publishing will be available later") {}
                    .disabled(true)
            }
        }
        .navigationTitle("Create News")
    }
}

#Preview {
    NavigationStack {
        NewsEditorPlaceholderView()
    }
}
