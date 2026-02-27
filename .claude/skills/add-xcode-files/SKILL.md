---
name: add-xcode-files
description: Add newly created Swift files to the Xcode project (project.pbxproj).
disable-model-invocation: true
---

# Add Files to Xcode Project

After creating new `.swift` files, they must be added to `project.pbxproj` to be included in the build.

## When to Use

Run this after creating **any** new `.swift` file in the project. Files not added to the Xcode project will not compile.

## Usage

```bash
python3 .claude/skills/add-xcode-files/scripts/add_to_xcodeproj.py \
    VultisigApp/VultisigApp.xcodeproj/project.pbxproj \
    "VultisigApp/VultisigApp/Path/To/NewFile.swift"
```

**Multiple files:**
```bash
python3 .claude/skills/add-xcode-files/scripts/add_to_xcodeproj.py \
    VultisigApp/VultisigApp.xcodeproj/project.pbxproj \
    "VultisigApp/VultisigApp/Path/To/File1.swift" \
    "VultisigApp/VultisigApp/Path/To/File2.swift"
```

## What It Does

1. Creates a backup of `project.pbxproj` (`.bak`)
2. Generates unique 24-character hex UUIDs for each entry
3. Adds `PBXFileReference` entries (file registration)
4. Adds `PBXBuildFile` entries (compile source)
5. Adds files to the appropriate `PBXGroup` (directory grouping)
6. Adds to `PBXSourcesBuildPhase` (build inclusion)

## Verification

After running, confirm the file compiles:
```bash
xcodebuild -project VultisigApp/VultisigApp.xcodeproj -scheme VultisigApp -sdk iphonesimulator build 2>&1 | tail -5
```
