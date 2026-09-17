import os
import sys

def check_brackets(file_path):
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    stack = []
    in_string = False
    in_multi_string = False
    in_comment = False
    in_multi_comment = False

    i = 0
    while i < len(content):
        c = content[i]

        if in_multi_comment:
            if c == '*' and i + 1 < len(content) and content[i+1] == '/':
                in_multi_comment = False
                i += 1
        elif in_comment:
            if c == '\n':
                in_comment = False
        elif in_multi_string:
            if c == '"' and i + 2 < len(content) and content[i+1] == '"' and content[i+2] == '"':
                in_multi_string = False
                i += 2
            elif c == '\\' and i + 1 < len(content) and content[i+1] == '(':
                stack.append(('\\(', i))
                i += 1
        elif in_string:
            if c == '"':
                in_string = False
            elif c == '\\' and i + 1 < len(content) and content[i+1] == '(':
                stack.append(('\\(', i))
                i += 1
            elif c == '\\':
                i += 1
        else:
            if c == '/' and i + 1 < len(content) and content[i+1] == '/':
                in_comment = True
                i += 1
            elif c == '/' and i + 1 < len(content) and content[i+1] == '*':
                in_multi_comment = True
                i += 1
            elif c == '"' and i + 2 < len(content) and content[i+1] == '"' and content[i+2] == '"':
                in_multi_string = True
                i += 2
            elif c == '"':
                in_string = True
            elif c in '{[(':
                stack.append((c, i))
            elif c in '}])':
                if not stack:
                    return False, f"Unmatched closing bracket '{c}' at index {i}"
                top_c, top_i = stack.pop()
                if (c == '}' and top_c not in '{' and top_c != '\\(') or \
                   (c == ']' and top_c != '[') or \
                   (c == ')' and top_c != '('):
                    return False, f"Mismatched bracket: expected match for '{top_c}' at index {top_i}, found '{c}' at index {i}"

        i += 1

    return True, ""

ok, err = check_brackets("XboxControllerMapper/XboxControllerMapperTests/OBSWebSocketLiveIntegrationTests.swift")
if not ok:
    print(err)
else:
    print("Syntax check passed")
