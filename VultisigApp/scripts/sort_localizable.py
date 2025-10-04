import re
import sys

if len(sys.argv) != 2:
    print("Usage: python3 sort_localizable.py <Localizable.strings>")
    sys.exit(1)

input_file = sys.argv[1]
output_file = input_file + ".sorted"

entries = []

with open(input_file, 'r', encoding='utf-8') as f:
    for line in f:
        match = re.match(r'\s*"([^"]+)"\s*=\s*"([^"]*)";', line)
        if match:
            key = match.group(1)
            value = match.group(2)
            entries.append((key, value))

entries.sort(key=lambda x: x[0].lower())

with open(output_file, 'w', encoding='utf-8') as f:
    for key, value in entries:
        f.write(f'"{key}" = "{value}";\n')

print(f"Sorted file written to {output_file}")
