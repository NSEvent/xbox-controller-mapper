import sys

filepath = 'XboxControllerMapper/XboxControllerMapper/Views/Macros/MacroEditorSheet.swift'
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# Update AddStepRow to use Button
search_addstep = """        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
            Text("Add Step")
                .font(.system(size: 13))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
        .background(isHovered ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            onTap()
        }"""

replace_addstep = """        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                Text("Add Step")
                    .font(.system(size: 13))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            .background(isHovered ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor).opacity(0.3))
            .cornerRadius(6)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .buttonStyle(.plain)
        .help("Add new macro step")
        .accessibilityLabel("Add new macro step")"""

# Update MacroStepRow to accept onEdit
search_macrosteprow_def = """struct MacroStepRow: View {
    let step: MacroStep
    let index: Int
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))

            Text("\\(index + 1).")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .leading)

            icon
                .frame(width: 20)

            Text(step.displayString)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()"""

replace_macrosteprow_def = """struct MacroStepRow: View {
    let step: MacroStep
    let index: Int
    var onEdit: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))

            Button(action: onEdit) {
                HStack(spacing: 8) {
                    Text("\\(index + 1).")
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
            .help("Edit Step \\(index + 1)")
            .accessibilityLabel("Edit Step \\(index + 1)")"""

# Update MacroEditorSheet caller site
search_caller = """                        MacroStepRow(
                            step: identifiedStep.step,
                            index: index,
                            onDuplicate: { duplicateStep(at: index) },
                            onDelete: { deleteStep(at: index) }
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingStepIndex = index
                            showingStepEditor = true
                        }"""

replace_caller = """                        MacroStepRow(
                            step: identifiedStep.step,
                            index: index,
                            onEdit: {
                                editingStepIndex = index
                                showingStepEditor = true
                            },
                            onDuplicate: { duplicateStep(at: index) },
                            onDelete: { deleteStep(at: index) }
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                        .contentShape(Rectangle())"""

if search_addstep in content and search_macrosteprow_def in content and search_caller in content:
    content = content.replace(search_addstep, replace_addstep)
    content = content.replace(search_macrosteprow_def, replace_macrosteprow_def)
    content = content.replace(search_caller, replace_caller)
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print("Successfully replaced all blocks without nested buttons.")
else:
    print("Search block not found.")
    if search_addstep not in content: print("addstep failed")
    if search_macrosteprow_def not in content: print("macrosteprow_def failed")
    if search_caller not in content: print("caller failed")
