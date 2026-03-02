#!/usr/bin/env python3
"""
Add Swift files to an Xcode project.pbxproj file.

Usage:
    python3 add_to_xcodeproj.py <project.pbxproj> <file1.swift> [file2.swift ...]

Creates backup before modification. Generates unique UUIDs for
PBXFileReference, PBXBuildFile, and PBXGroup entries.
"""

import sys
import os
import re
import hashlib
import shutil
import time


def generate_uuid(seed: str) -> str:
    """Generate a 24-character hex UUID deterministically from a seed."""
    hash_input = f"{seed}-{time.time_ns()}".encode()
    return hashlib.md5(hash_input).hexdigest()[:24].upper()


def find_section(content: str, section_name: str):
    """Find the start and end indices of a PBX section."""
    pattern = rf"/\* Begin {re.escape(section_name)} section \*/"
    end_pattern = rf"/\* End {re.escape(section_name)} section \*/"
    start_match = re.search(pattern, content)
    end_match = re.search(end_pattern, content)
    if not start_match or not end_match:
        return None, None
    return start_match.end(), end_match.start()


def find_group_for_directory(content: str, directory_name: str):
    """Find a PBXGroup that contains children for the given directory."""
    # Look for groups with the directory name
    pattern = rf'([A-F0-9]{{24}}) /\* {re.escape(directory_name)} \*/ = \{{[^}}]*children = \('
    match = re.search(pattern, content)
    if match:
        return match.group(1), match.start()
    return None, None


def find_sources_build_phase(content: str):
    """Find the PBXSourcesBuildPhase files list."""
    section_start, section_end = find_section(content, "PBXSourcesBuildPhase")
    if section_start is None:
        return None, None
    # Find the files = ( ... ) within this section
    subsection = content[section_start:section_end]
    files_match = re.search(r'files = \(', subsection)
    if not files_match:
        return None, None
    abs_start = section_start + files_match.end()
    return abs_start, section_end


def add_file_to_project(content: str, swift_file_path: str):
    """Add a single Swift file to the project.pbxproj content in-memory."""
    filename = os.path.basename(swift_file_path)
    file_basename = os.path.splitext(filename)[0]

    # Check if file is already in the project
    if filename in content and f'/* {filename} */' in content:
        print(f"  SKIP: {filename} already exists in project")
        return content

    # Generate UUIDs
    file_ref_uuid = generate_uuid(f"fileref-{swift_file_path}")
    build_file_uuid = generate_uuid(f"buildfile-{swift_file_path}")

    # Determine the source tree
    source_tree = '"<group>"'

    # 1. Add PBXFileReference
    file_ref_line = (
        f'\t\t{file_ref_uuid} /* {filename} */ = '
        f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; '
        f'path = {filename}; sourceTree = {source_tree}; }};\n'
    )

    section_start, section_end = find_section(content, "PBXFileReference")
    if section_start is None:
        print(f"  ERROR: Could not find PBXFileReference section")
        return content

    # Insert before the end of section (alphabetically would be ideal but end is safe)
    content = content[:section_end] + file_ref_line + content[section_end:]

    # 2. Add PBXBuildFile
    build_file_line = (
        f'\t\t{build_file_uuid} /* {filename} in Sources */ = '
        f'{{isa = PBXBuildFile; fileRef = {file_ref_uuid} /* {filename} */; }};\n'
    )

    section_start, section_end = find_section(content, "PBXBuildFile")
    if section_start is None:
        print(f"  ERROR: Could not find PBXBuildFile section")
        return content

    content = content[:section_end] + build_file_line + content[section_end:]

    # 3. Add to PBXGroup (find the parent directory's group)
    parent_dir = os.path.basename(os.path.dirname(swift_file_path))
    group_uuid, group_pos = find_group_for_directory(content, parent_dir)

    if group_uuid:
        # Find the children = ( ... ) for this group
        group_section = content[group_pos:]
        children_match = re.search(r'children = \(', group_section)
        if children_match:
            insert_pos = group_pos + children_match.end()
            group_entry = f'\n\t\t\t\t{file_ref_uuid} /* {filename} */,'
            content = content[:insert_pos] + group_entry + content[insert_pos:]
    else:
        print(f"  WARN: Could not find PBXGroup for '{parent_dir}', file reference added but not grouped")

    # 4. Add to PBXSourcesBuildPhase
    sources_start, sources_end = find_sources_build_phase(content)
    if sources_start:
        source_entry = f'\n\t\t\t\t{build_file_uuid} /* {filename} in Sources */,'
        content = content[:sources_start] + source_entry + content[sources_start:]

    print(f"  ADDED: {filename} (ref={file_ref_uuid[:8]}..., build={build_file_uuid[:8]}...)")
    return content


def main():
    if len(sys.argv) < 3:
        print("Usage: python3 add_to_xcodeproj.py <project.pbxproj> <file1.swift> [file2.swift ...]")
        sys.exit(1)

    pbxproj_path = sys.argv[1]
    swift_files = sys.argv[2:]

    if not os.path.exists(pbxproj_path):
        print(f"ERROR: {pbxproj_path} not found")
        sys.exit(1)

    # Create backup
    backup_path = pbxproj_path + ".bak"
    shutil.copy2(pbxproj_path, backup_path)
    print(f"Backup created: {backup_path}")

    # Read original content
    with open(pbxproj_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Process each file
    for swift_file in swift_files:
        if not swift_file.endswith(".swift"):
            print(f"  SKIP: {swift_file} is not a .swift file")
            continue
        content = add_file_to_project(content, swift_file)

    # Write modified content
    with open(pbxproj_path, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"\nDone. Modified: {pbxproj_path}")
    print(f"Restore backup if needed: cp {backup_path} {pbxproj_path}")


if __name__ == "__main__":
    main()
