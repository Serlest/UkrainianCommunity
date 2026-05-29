import SwiftUI

struct GuideStepsContentBlockEditor: View {
    @Binding var block: GuideContentBlock

    var body: some View {
        if case .steps(let value) = block {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                GuideContentBlockTitleField(title: value.title) { title in
                    block = .steps(.init(id: value.id, title: title, steps: value.steps))
                }

                AppEditorField(title: AppStrings.GuideEditor.blockStepsField) {
                    if value.steps.isEmpty {
                        Text(AppStrings.GuideEditor.blockStepsEmpty)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                            ForEach(value.steps.indices, id: \.self) { index in
                                GuideStepEditorRow(
                                    text: value.steps[index],
                                    canMoveUp: index > 0,
                                    canMoveDown: index < value.steps.count - 1,
                                    onChange: { updateStep(at: index, text: $0, in: value) },
                                    onMoveUp: { moveStep(from: index, to: index - 1, in: value) },
                                    onMoveDown: { moveStep(from: index, to: index + 1, in: value) },
                                    onDelete: { deleteStep(at: index, in: value) }
                                )
                            }
                        }
                    }

                    Button {
                        appendStep(to: value)
                    } label: {
                        Label(AppStrings.GuideEditor.addStep, systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func appendStep(to value: GuideContentBlock.StepsBlock) {
        var steps = value.steps
        steps.append("")
        block = .steps(.init(id: value.id, title: value.title, steps: steps))
    }

    private func updateStep(at index: Int, text: String, in value: GuideContentBlock.StepsBlock) {
        guard value.steps.indices.contains(index) else { return }
        var steps = value.steps
        steps[index] = text
        block = .steps(.init(id: value.id, title: value.title, steps: steps))
    }

    private func moveStep(from source: Int, to destination: Int, in value: GuideContentBlock.StepsBlock) {
        guard value.steps.indices.contains(source), value.steps.indices.contains(destination) else { return }
        var steps = value.steps
        let step = steps.remove(at: source)
        steps.insert(step, at: destination)
        block = .steps(.init(id: value.id, title: value.title, steps: steps))
    }

    private func deleteStep(at index: Int, in value: GuideContentBlock.StepsBlock) {
        guard value.steps.indices.contains(index) else { return }
        var steps = value.steps
        steps.remove(at: index)
        block = .steps(.init(id: value.id, title: value.title, steps: steps))
    }
}

private struct GuideStepEditorRow: View {
    let text: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onChange: (String) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
            TextEditor(text: Binding(get: { text }, set: onChange))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 64)
                .padding(8)
                .background(AppTheme.surfaceGlass, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                .accessibilityLabel(AppStrings.GuideEditor.stepTextPlaceholder)

            VStack(spacing: 4) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveUp)
                .accessibilityLabel(AppStrings.GuideEditor.moveStepUp)

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveDown)
                .accessibilityLabel(AppStrings.GuideEditor.moveStepDown)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(AppStrings.GuideEditor.deleteStep)
            }
            .buttonStyle(.borderless)
        }
    }
}
