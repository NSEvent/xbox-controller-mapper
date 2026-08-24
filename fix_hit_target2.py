import os

def process_file(filepath, before, after):
    with open(filepath, 'r') as f:
        content = f.read()
    if before in content:
        with open(filepath, 'w') as f:
            f.write(content.replace(before, after))
        print(f"Updated {filepath}")
    else:
        print(f"Not found in {filepath}")

gesture_file = "./XboxControllerMapper/XboxControllerMapper/Views/MainWindow/GestureListViews.swift"
gesture_before = """        HStack {
            Button(action: onEdit) {
                HStack {
                    // Gesture icon and name
                    HStack(spacing: 8) {
                        Image(systemName: gestureType.iconName)
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)
                            .frame(width: 24)

                        Text(gestureType.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    }

                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.3))
                        .accessibilityHidden(true)

                    // Action display
                    if let mapping = mapping, mapping.hasAction {
                        actionText(for: mapping)
                    } else {
                        Text("Not Mapped")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .italic()
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Action buttons
            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .help("Edit \\(gestureType.displayName)")
                .accessibilityLabel("Edit \\(gestureType.displayName)")

                if mapping?.hasAction == true {
                    Button(action: onClear) {
                        Image(systemName: "trash")
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.borderless)
                    .help("Clear \\(gestureType.displayName)")
                    .accessibilityLabel("Clear \\(gestureType.displayName)")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)"""

gesture_after = """        HStack {
            Button(action: onEdit) {
                HStack {
                    // Gesture icon and name
                    HStack(spacing: 8) {
                        Image(systemName: gestureType.iconName)
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)
                            .frame(width: 24)

                        Text(gestureType.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    }

                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.3))
                        .accessibilityHidden(true)

                    // Action display
                    if let mapping = mapping, mapping.hasAction {
                        actionText(for: mapping)
                    } else {
                        Text("Not Mapped")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .italic()
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Action buttons
            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .help("Edit \\(gestureType.displayName)")
                .accessibilityLabel("Edit \\(gestureType.displayName)")

                if mapping?.hasAction == true {
                    Button(action: onClear) {
                        Image(systemName: "trash")
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.borderless)
                    .help("Clear \\(gestureType.displayName)")
                    .accessibilityLabel("Clear \\(gestureType.displayName)")
                }
            }
            .padding(.trailing, 12)
            .padding(.vertical, 8)
        }"""
process_file(gesture_file, gesture_before, gesture_after)
