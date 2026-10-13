#!/bin/zsh
set -euo pipefail
repo="${0:A:h:h}"
directory="$repo/UkrainianCommunity/Features/Directory"
output="$repo/Android/app/src/main/assets/directory-catalog.json"
mkdir -p "${output:h}"
sources=(
  "$directory"/*Guides*.swift(N)
  "$directory"/*RegionalContent*.swift(N)
  "$directory"/DirectoryCatalog*.swift(N)
  "$directory"/DirectoryCategory.swift
  "$directory"/DirectoryTopicGroups.swift
  "$directory"/DirectorySafetyContent*.swift(N)
  "$directory"/DirectoryManagedModels.swift
  "$directory"/DirectoryGuide.swift
)
swiftc "$repo/Scripts/export_android_directory.swift" "${sources[@]}" -o /tmp/uac-export-android-directory
/tmp/uac-export-android-directory > "$output"
print "Exported ${output}"
