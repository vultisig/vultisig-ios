---
name: add-xcode-files
description: Add newly created Swift files to the Xcode project (project.pbxproj).
disable-model-invocation: true
---

# Add Files to Xcode Project

**CRITICAL:** This project uses explicit file references in `project.pbxproj`, NOT folder references. Creating a new `.swift` file on disk is NOT enough — it must also be registered in the Xcode project or it will not compile.

## When to Use

Run this after creating **any** new `.swift` file in the project.

## Usage

Use the `xcodeproj` Ruby gem (pre-installed) to add files programmatically:

```ruby
cat << 'RUBY' | ruby
require 'xcodeproj'

project_path = 'VultisigApp/VultisigApp.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'VultisigApp' }

def find_or_create_group(project, path_components)
  current_group = project.main_group
  path_components.each do |component|
    child = current_group.children.find { |c| c.display_name == component }
    if child && child.is_a?(Xcodeproj::Project::Object::PBXGroup)
      current_group = child
    else
      current_group = current_group.new_group(component, component)
    end
  end
  current_group
end

# === EDIT BELOW: set the group path and file list ===

# Group path: directory components under VultisigApp/ where files live
# Example: ['VultisigApp', 'Features', 'MyFeature']
group = find_or_create_group(project, ['VultisigApp', 'PATH', 'TO', 'DIRECTORY'])

# Files to add (filenames only, must already exist on disk at the group path)
['NewFile.swift'].each do |filename|
  next if group.children.find { |c| c.display_name == filename }
  file_ref = group.new_file(filename)
  target.source_build_phase.add_file_reference(file_ref)
end

# === EDIT ABOVE ===

project.save
RUBY
```

## What It Does

1. Opens the Xcode project using the `xcodeproj` gem (proper parser, not regex)
2. Navigates to the correct `PBXGroup` (creates intermediate groups if needed)
3. Adds `PBXFileReference` entries (file registration)
4. Adds `PBXBuildFile` entries (compile source)
5. Adds files to `PBXSourcesBuildPhase` (build inclusion)
6. Saves the project atomically

## Verification

After running, confirm the file compiles:
```bash
xcodebuild -project VultisigApp/VultisigApp.xcodeproj -scheme VultisigApp -sdk iphonesimulator build 2>&1 | tail -5
```
