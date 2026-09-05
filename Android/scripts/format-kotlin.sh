#!/bin/bash
set -euo pipefail

# This helper is deliberately scoped to Android source and build scripts, never the iOS tree.
cd "$(dirname "$0")/.."
uac_mode="${1:---check}"
if [[ "$#" -gt 1 || ( "$uac_mode" != "--check" && "$uac_mode" != "--write" ) ]]; then
    printf 'Usage: bash scripts/format-kotlin.sh [--check|--write]\n' >&2
    exit 2
fi

uac_version="0.64"
uac_expected_sha="b8fbb814808d8da33f74a7bbacb6d1748cef81c0202a7f829b87139520b51273"
uac_jar="${UAC_KTFMT_JAR:-$PWD/.gradle/uac-tools/ktfmt-$uac_version-with-dependencies.jar}"
uac_valid_jar() {
    [[ -f "$uac_jar" ]] && [[ "$(shasum -a 256 "$uac_jar" | awk '{print $1}')" == "$uac_expected_sha" ]]
}

if ! uac_valid_jar; then
    if [[ -n "${UAC_KTFMT_JAR:-}" || -e "$uac_jar" ]]; then
        printf 'The formatter is absent or its SHA-256 does not match the pinned release. No source was changed.\n' >&2
        exit 3
    fi
    mkdir -p "$PWD/.gradle/uac-tools"
    uac_temp_dir="$(mktemp -d "$PWD/.gradle/uac-tools/download.XXXXXX")"
    trap 'rm -f "$uac_temp_dir/ktfmt.jar"; rmdir "$uac_temp_dir"' EXIT
    curl --fail --location --proto '=https' --tlsv1.2 \
        --output "$uac_temp_dir/ktfmt.jar" \
        "https://github.com/Kotlin/ktfmt/releases/download/v$uac_version/ktfmt-$uac_version-with-dependencies.jar"
    if [[ "$(shasum -a 256 "$uac_temp_dir/ktfmt.jar" | awk '{print $1}')" != "$uac_expected_sha" ]]; then
        printf 'Downloaded formatter checksum mismatch. No source was changed.\n' >&2
        exit 3
    fi
    mv "$uac_temp_dir/ktfmt.jar" "$uac_jar"
fi

uac_files=(build.gradle.kts settings.gradle.kts app/build.gradle.kts pushprobe/build.gradle.kts)
while IFS= read -r uac_file; do
    uac_files+=("$uac_file")
done < <(rg --files app/src pushprobe/src -g '*.kt' | LC_ALL=C sort)

uac_options=(--kotlinlang-style --do-not-remove-unused-imports --quiet)
uac_java="${JAVA_HOME:+$JAVA_HOME/bin/}java"
if [[ "$uac_mode" == "--check" ]]; then
    exec "$uac_java" -jar "$uac_jar" "${uac_options[@]}" --dry-run --set-exit-if-changed "${uac_files[@]}"
fi
# Removing old statement separators may expose a second layout pass. Require convergence.
for uac_pass in 1 2 3; do
    "$uac_java" -jar "$uac_jar" "${uac_options[@]}" "${uac_files[@]}"
    if "$uac_java" -jar "$uac_jar" "${uac_options[@]}" --dry-run --set-exit-if-changed "${uac_files[@]}" > /dev/null; then
        exit 0
    fi
done
printf 'Formatting did not converge after three passes; review the changed files before continuing.\n' >&2
exit 4
