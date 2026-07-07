import re

with open('TriggerKit/Tests/TriggerKitRuntimeTests/AutomationExecutorTests.swift', 'r') as f:
    content = f.read()

pattern = r'func\s+testShellCommandDrainsLargeOutputWithoutDeadlocking'
match = re.search(pattern, content)

start_index = match.end()

while content[start_index] != '{':
    start_index += 1

count = 1
i = start_index + 1
in_string = False

while i < len(content):
    if content[i] == '"' and (i == 0 or content[i-1] != '\\'):
        in_string = not in_string

    if not in_string:
        if content[i] == '{':
            count += 1
        elif content[i] == '}':
            count -= 1
            if count == 0:
                print(content[match.start():i+1])
                break
    i += 1
