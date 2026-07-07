import re

with open('TriggerKit/Tests/TriggerKitRuntimeTests/AutomationExecutorTests.swift', 'r') as f:
    content = f.read()

funcs = re.findall(r'func\s+(test\w+)', content)
for func in funcs:
    print(func)
