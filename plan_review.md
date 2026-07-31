I should undo the `MacroEditorSheet` changes in `ForEach` and instead move the tap action logic down to `MacroStepRow`.
Wait, in `MacroStepRow` it looks like:
```swift
struct MacroStepRow: View {
    let step: MacroStep
    let index: Int
    var onDuplicate: () -> Void
    var onDelete: () -> Void
    // ADD: var onEdit: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))

            // wrap from here to Spacer in a Button(action: onEdit) ?
            Button(action: onEdit) {
                HStack(spacing: 8) {
                    Text("\(index + 1).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 20, alignment: .leading)

                    icon
                        .frame(width: 20)

                    Text(step.displayString)
                        .font(.system(size: 13))
                        .lineLimit(1)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit Step \(index + 1)")
            .accessibilityLabel("Edit Step \(index + 1)")

            Button {
                onDuplicate()
            } label: { ... }

            Button {
                onDelete()
            } label: { ... }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(isHovered ? .accentColor : .secondary.opacity(0.5))
        }
    }
}
```
Wait, currently the `.onTapGesture` is applied to the **entire row** from the outside!
```swift
                        MacroStepRow(
                            step: identifiedStep.step,
                            index: index,
                            onDuplicate: { duplicateStep(at: index) },
                            onDelete: { deleteStep(at: index) }
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(...)
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingStepIndex = index
                            showingStepEditor = true
                        }
```
If we apply it via `onTapGesture` to the outside, it works, except it lacks accessibility.
If we change the outside to wrap `MacroStepRow` in a `Button`, SwiftUI complains about nested buttons, which is known to cause crashes or failure in tests.

Let's do this: I will restore `MacroEditorSheet.swift` entirely to origin/main and apply the correct fix inside `MacroStepRow`.
Wait, no. The outside `ForEach` loop has `.onDrag` and `.onDrop`. I can just modify `MacroStepRow` to accept an `onEdit` closure, and inside `MacroStepRow`, wrap the main tappable area in a `Button`.
But wait! The background color and hover effect in `MacroStepRow` is applied to the outer `HStack` inside `MacroStepRow`, OR is it applied from outside?
Looking at `MacroEditorSheet.swift`:
```swift
                        MacroStepRow(...)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                        .onTapGesture { ... }
```
It is applied from outside!
If I remove `.onTapGesture` from outside, I should pass `onEdit` to `MacroStepRow`.

Let's test reverting `MacroEditorSheet.swift` to origin/main first, to ensure that the tests pass. If the test passes after I revert `MacroEditorSheet.swift` but leave `MacroListView.swift`, I'll know exactly what caused it.
