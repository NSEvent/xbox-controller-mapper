import sys

def check_syntax(filepath):
    try:
        with open(filepath, 'r') as f:
            content = f.read()

        stack = []
        lines = content.split('\n')

        in_multiline_string = False
        in_multiline_comment = False

        for line_num, line in enumerate(lines, 1):
            i = 0
            while i < len(line):
                # Handle multiline string
                if not in_multiline_comment and line[i:i+3] == '"""':
                    in_multiline_string = not in_multiline_string
                    i += 3
                    continue

                if in_multiline_string:
                    i += 1
                    continue

                # Handle multiline comment
                if not in_multiline_string and line[i:i+2] == '/*':
                    in_multiline_comment = True
                    i += 2
                    continue

                if not in_multiline_string and line[i:i+2] == '*/':
                    in_multiline_comment = False
                    i += 2
                    continue

                if in_multiline_comment:
                    i += 1
                    continue

                # Handle single line string
                if line[i] == '"' and (i == 0 or line[i-1] != '\\'):
                    i += 1
                    # Skip to end of string or end of line
                    while i < len(line):
                        if line[i] == '"' and line[i-1] != '\\':
                            i += 1
                            break
                        i += 1
                    continue

                # Handle single line comment
                if line[i:i+2] == '//':
                    break # Rest of line is comment

                # Check brackets/braces/parens outside of strings/comments
                char = line[i]
                if char in '({[':
                    stack.append((char, line_num))
                elif char in ')}]':
                    if not stack:
                        print(f"Error in {filepath}: Unmatched '{char}' at line {line_num}")
                        return False

                    last_char, _ = stack.pop()
                    if (char == ')' and last_char != '(') or \
                       (char == '}' and last_char != '{') or \
                       (char == ']' and last_char != '['):
                        print(f"Error in {filepath}: Mismatched '{char}' at line {line_num}. Expected match for '{last_char}'")
                        return False

                i += 1

        if stack:
            print(f"Error in {filepath}: Unclosed symbols remaining: {stack}")
            return False

        print(f"Success: Syntax check passed for {filepath}")
        return True

    except Exception as e:
        print(f"Error processing {filepath}: {e}")
        return False

files = [
    "XboxControllerMapper/XboxControllerMapper/Views/Macros/MacroListView.swift",
    "XboxControllerMapper/XboxControllerMapper/Views/Scripts/ScriptListView.swift"
]

all_passed = True
for f in files:
    if not check_syntax(f):
        all_passed = False

if not all_passed:
    sys.exit(1)
