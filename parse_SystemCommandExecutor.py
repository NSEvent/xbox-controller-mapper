import re

with open('XboxControllerMapper/XboxControllerMapper/Services/Input/SystemCommandExecutor.swift', 'r') as f:
    content = f.read()

pattern = r'waitUntilExit\(\)'
for match in re.finditer(pattern, content):
    start = max(0, match.start() - 200)
    end = min(len(content), match.end() + 200)
    print(f"--- MATCH AT {match.start()} ---")
    print(content[start:end])
