import sys
import re

filepath = 'XboxControllerMapper/XboxControllerMapper/Views/MainWindow/ChordSequenceListViews.swift'

with open(filepath, 'r') as f:
    content = f.read()

content = content.replace(r"""                        ForEach(Array(sequence.steps.enumerated()), id: \.offset) { index, button in
                        if index > 0 {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.3))
                                .accessibilityHidden(true)
                        }""", r"""                        ForEach(Array(sequence.steps.enumerated()), id: \.offset) { index, button in
                            if index > 0 {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.3))
                                    .accessibilityHidden(true)
                            }""")

with open(filepath, 'w') as f:
    f.write(content)
