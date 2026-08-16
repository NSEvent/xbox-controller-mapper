import sys

def replace_in_file(filepath, replacements):
    with open(filepath, 'r') as f:
        content = f.read()

    modified = False
    for search, replace in replacements:
        if search in content:
            content = content.replace(search, replace)
            modified = True
        else:
            print(f"Warning: Could not find block in {filepath}:\n{search}")

    if modified:
        with open(filepath, 'w') as f:
            f.write(content)
        print(f"Successfully modified {filepath}")
    return modified

replacements = [
    (
        """\t\t\t\t#if DEBUG
\t\t\t\tprint("🔷 Layer activated: \\(layer.name)")
\t\t\t\t#endif""",
        """\t\t\t\t// Memory: Excessive synchronous logging in hot paths causes XCTest deadlocks.
\t\t\t\t// Omit print("🔷 Layer activated...")"""
    ),
    (
        """\t\t\t\t#if DEBUG
\t\t\t\tprint("🔷 Layer deactivated: \\(layer.name)")
\t\t\t\t#endif""",
        """\t\t\t\t// Memory: Excessive synchronous logging in hot paths causes XCTest deadlocks.
\t\t\t\t// Omit print("🔷 Layer deactivated...")"""
    ),
    (
        """\t\t\t\t#if DEBUG
\t\t\t\tprint("🔷 Layer activated via chord: \\(layer.name)")
\t\t\t\t#endif""",
        """\t\t\t\t// Memory: Excessive synchronous logging in hot paths causes XCTest deadlocks.
\t\t\t\t// Omit print("🔷 Layer activated via chord...")"""
    ),
    (
        """\t\t\t\t#if DEBUG
\t\t\t\tlet verb = isActive ? "on" : "off"
\t\t\t\tprint("🔷 Layer toggled \\(verb): \\(layer.name)")
\t\t\t\t#endif""",
        """\t\t\t\t// Memory: Excessive synchronous logging in hot paths causes XCTest deadlocks.
\t\t\t\t// Omit print("🔷 Layer toggled...")"""
    ),
]
replace_in_file("XboxControllerMapper/XboxControllerMapper/Services/Mapping/MappingEngine.swift", replacements)
