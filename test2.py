import re

filepath = "./XboxControllerMapper/XboxControllerMapper/Views/MainWindow/OnScreenKeyboardSettingsView.swift"
with open(filepath, 'r') as f:
    content = f.read()

# Let's inspect the code I added
for line in content.split('\n'):
    if 'help("Edit' in line or 'accessibilityLabel' in line or 'help("Delete' in line:
        print(line.strip())
