import sys

def process_file(filepath):
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()

        new_lines = []
        in_target_block = False
        target_block_start = -1

        for i, line in enumerate(lines):
            # Target start
            if line.rstrip() == "            // Tappable content area":
                if i + 1 < len(lines) and lines[i+1].rstrip() == "            HStack {":
                    new_lines.append(line)
                    new_lines.append("            Button(action: onEdit) {\n")
                    new_lines.append("                HStack {\n")
                    in_target_block = True
                    target_block_start = i
                    continue

            if in_target_block:
                if i == target_block_start or i == target_block_start + 1:
                    continue # already handled

                if line.rstrip() == "            }":
                    if i + 2 < len(lines) and lines[i+1].strip() == ".contentShape(Rectangle())" and lines[i+2].strip() == ".onTapGesture { onEdit() }":
                        new_lines.append("                }\n")
                        new_lines.append("                .contentShape(Rectangle())\n")
                        new_lines.append("            }\n")
                        new_lines.append("            .buttonStyle(.plain)\n")
                        in_target_block = False
                        continue

                # Indent everything inside by 4 spaces
                if line.startswith("            "):
                    new_lines.append("    " + line)
                else:
                    new_lines.append(line)
            else:
                if not (i > 0 and lines[i-1].strip() == ".contentShape(Rectangle())" and line.strip() == ".onTapGesture { onEdit() }") and \
                   not (i > 1 and lines[i-2].strip() == "}" and lines[i-1].strip() == ".contentShape(Rectangle())" and line.strip() == ".onTapGesture { onEdit() }"):
                    # Only append if we aren't skipping the old end block

                    # Need to explicitly avoid adding the original end lines since they are replaced
                    if line.strip() == ".contentShape(Rectangle())" and i + 1 < len(lines) and lines[i+1].strip() == ".onTapGesture { onEdit() }":
                         pass # skip
                    elif line.strip() == ".onTapGesture { onEdit() }" and i > 0 and lines[i-1].strip() == ".contentShape(Rectangle())":
                         pass # skip
                    else:
                        new_lines.append(line)

        with open(filepath, 'w') as f:
            f.writelines(new_lines)

        print(f"Processed {filepath}")

    except Exception as e:
        print(f"Error processing {filepath}: {e}")

process_file("XboxControllerMapper/XboxControllerMapper/Views/Macros/MacroListView.swift")
process_file("XboxControllerMapper/XboxControllerMapper/Views/Scripts/ScriptListView.swift")
