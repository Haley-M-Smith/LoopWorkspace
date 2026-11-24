#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
root="$PWD"

for module in Loop LoopKit; do
    patch="$root/CustomPatches/$module-pastel.patch"
    git -C "$module" apply --check --whitespace=error-all "$patch"
done

for module in Loop LoopKit; do
    patch="$root/CustomPatches/$module-pastel.patch"
    git -C "$module" apply --whitespace=error-all "$patch"
done
