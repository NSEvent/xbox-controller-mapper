import sys
import os

def check_brackets(file_path):
    try:
        with open(file_path, "r") as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Error: {file_path} not found.")
        return False

    stack = []
    line_num = 1

    in_string = False
    in_multi_line_string = False
    in_single_comment = False
    in_multi_comment = False
    escape_next = False

    i = 0
    while i < len(content):
        char = content[i]

        if char == '\n':
            line_num += 1
            in_single_comment = False

        if escape_next:
            escape_next = False
            i += 1
            continue

        if char == '\\':
            escape_next = True
            i += 1
            continue

        if not in_string and not in_multi_line_string and not in_single_comment and not in_multi_comment:
            if char == '/' and i + 1 < len(content) and content[i+1] == '/':
                in_single_comment = True
                i += 1
            elif char == '/' and i + 1 < len(content) and content[i+1] == '*':
                in_multi_comment = True
                i += 1
            elif char == '"' and i + 2 < len(content) and content[i:i+3] == '"""':
                in_multi_line_string = True
                i += 2
            elif char == '"':
                in_string = True
            elif char in "{[(":
                stack.append((char, line_num))
            elif char in "}])":
                if not stack:
                    print(f"Error in {file_path}: Unmatched closing bracket '{char}' at line {line_num}")
                    return False
                top, top_line = stack.pop()
                if (char == '}' and top != '{') or (char == ']' and top != '[') or (char == ')' and top != '('):
                    print(f"Error in {file_path}: Mismatched brackets at line {line_num}. Expected match for '{top}' from line {top_line}, got '{char}'")
                    return False
        elif in_string:
            if char == '"':
                in_string = False
        elif in_multi_line_string:
            if char == '"' and i + 2 < len(content) and content[i:i+3] == '"""':
                in_multi_line_string = False
                i += 2
        elif in_multi_comment:
            if char == '*' and i + 1 < len(content) and content[i+1] == '/':
                in_multi_comment = False
                i += 1

        i += 1

    if stack:
        top, top_line = stack.pop()
        print(f"Error in {file_path}: Unmatched opening bracket '{top}' from line {top_line}")
        return False

    return True

all_ok = True
for root, dirs, files in os.walk("."):
    for f in files:
        if f.endswith(".swift"):
            path = os.path.join(root, f)
            if not check_brackets(path):
                all_ok = False

if all_ok:
    print("All Swift files passed basic bracket validation.")
else:
    print("Some Swift files have bracket errors.")
    sys.exit(1)
