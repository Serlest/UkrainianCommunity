import SwiftUI

struct DirectoryMoveMenu: View {
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        Menu {
            Button {
                moveUp()
            } label: {
                Label(DirectoryEditorText.value("Підняти вище", "Nach oben verschieben"),
                      systemImage: "arrow.up")
            }
            .disabled(!canMoveUp)
            Button {
                moveDown()
            } label: {
                Label(DirectoryEditorText.value("Опустити нижче", "Nach unten verschieben"),
                      systemImage: "arrow.down")
            }
            .disabled(!canMoveDown)
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel(DirectoryEditorText.value("Змінити порядок", "Reihenfolge ändern"))
        }
        .disabled(!canMoveUp && !canMoveDown)
        .buttonStyle(.borderless)
    }
}
