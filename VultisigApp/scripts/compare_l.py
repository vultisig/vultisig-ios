import re

def extract_keys(filepath):
    keys = set()
    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            match = re.match(r'\"([^\"]+)\"\s*=', line)
            if match:
                keys.add(match.group(1))
    return keys

en_file = "VultisigApp/VultisigApp/Localizables/en.lproj/Localizable.strings"
de_file = "VultisigApp/VultisigApp/Localizables/de.lproj/Localizable.strings"
it_file = "VultisigApp/VultisigApp/Localizables/it.lproj/Localizable.strings"
es_file = "VultisigApp/VultisigApp/Localizables/es.lproj/Localizable.strings"
hr_file = "VultisigApp/VultisigApp/Localizables/hr.lproj/Localizable.strings"
pt_file = "VultisigApp/VultisigApp/Localizables/pt.lproj/Localizable.strings"

en_keys = extract_keys(en_file)
de_keys = extract_keys(de_file)
it_keys = extract_keys(it_file)
es_keys = extract_keys(es_file)
hr_keys = extract_keys(hr_file)
pt_keys = extract_keys(pt_file)

print(f"English keys: {len(en_keys)}")
print(f"German keys: {len(de_keys)}")
print(f"Italian keys: {len(it_keys)}")
print(f"Spanish keys: {len(es_keys)}")
print(f"Croatian keys: {len(hr_keys)}")
print(f"Portuguese keys: {len(pt_keys)}")
missing_in_en = sorted(en_keys - pt_keys)

print("Keys in English but not in Portuguese:")
for key in missing_in_en:
    print(key)