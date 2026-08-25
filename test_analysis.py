import os

filepath = 'XboxControllerMapper/XboxControllerMapper/Views/Macros/MacroListView.swift'

with open(filepath, 'r') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if 'struct MacroRow: View {' in line:
        print(f"Start of MacroRow at line {i+1}")
        for j in range(i, i+15):
            print(f"{j+1}: {lines[j].strip()}")
        break
