import sys
from pathlib import Path

def validate_swift_file(filepath):
    try:
        content = Path(filepath).read_text(encoding='utf-8')
    except Exception as e:
        return False, str(e)

    import re
    content = re.sub(r'"""[\s\S]*?"""', '', content)

    curly_open = content.count('{')
    curly_close = content.count('}')
    paren_open = content.count('(')
    paren_close = content.count(')')
    square_open = content.count('[')
    square_close = content.count(']')

    if curly_open != curly_close:
        return False, f"Unbalanced curly braces: {curly_open} open, {curly_close} close"
    if paren_open != paren_close:
        return False, f"Unbalanced parentheses: {paren_open} open, {paren_close} close"
    if square_open != square_close:
        return False, f"Unbalanced square brackets: {square_open} open, {square_close} close"

    return True, "Syntax appears balanced"

files_to_check = [
    'XboxControllerMapper/XboxControllerMapper/Views/Macros/MacroListView.swift',
    'XboxControllerMapper/XboxControllerMapper/Views/Macros/MacroEditorSheet.swift'
]

all_passed = True
for f in files_to_check:
    passed, msg = validate_swift_file(f)
    print(f"{f}: {msg}")
    if not passed:
        all_passed = False

if not all_passed:
    sys.exit(1)
