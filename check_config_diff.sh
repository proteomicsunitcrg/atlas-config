#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${1:-.}"
SOURCE_ENV="${2:-atlas-dev}"
TARGET_ENVS=("atlas-test" "atlas-main")

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ONLY_IN_SOURCE=()
ONLY_IN_TARGET=()
REAL_CHANGES=()

normalize_file() {
    local input_file="$1"
    local output_file="$2"

    sed -E \
        -e 's#/users/pr/proteomics/mygit/atlas-config/[^"[:space:]]+#<ATLAS_CONFIG_PATH>#g' \
        -e 's#/users/pr/proteomics/mygit/[^"[:space:]]+#<MYGIT_PATH>#g' \
        -e 's#/users/pr/data/[^"[:space:]]+#<DATA_PATH>#g' \
        -e 's#/scratch/[^"[:space:]]+#<SCRATCH_PATH>#g' \
        -e 's#/[A-Za-z0-9._/-]+#<ABSOLUTE_PATH>#g' \
        "$input_file" > "$output_file"
}

compare_envs() {
    local src="$1"
    local dst="$2"

    echo "=================================================="
    echo "Comparant: $src  vs  $dst"
    echo "=================================================="

    local diff_found=0

    while IFS= read -r -d '' relfile; do
        local src_file="$BASE_DIR/$src/$relfile"
        local dst_file="$BASE_DIR/$dst/$relfile"

        if [[ ! -f "$dst_file" ]]; then
            echo "[NOMES A $src] $relfile"
            ONLY_IN_SOURCE+=("$dst:$relfile")
            diff_found=1
            continue
        fi

        local safe_name
        safe_name="$(echo "${dst}_${relfile}" | tr '/ ' '__')"

        local norm_src="$TMP_DIR/${safe_name}_src"
        local norm_dst="$TMP_DIR/${safe_name}_dst"

        normalize_file "$src_file" "$norm_src"
        normalize_file "$dst_file" "$norm_dst"

        if ! diff -q -B -w "$norm_src" "$norm_dst" >/dev/null 2>&1; then
            echo
            echo "[CANVI REAL] $relfile"
            diff -u -B -w "$norm_dst" "$norm_src" || true
            REAL_CHANGES+=("$dst:$relfile")
            diff_found=1
        fi
    done < <(cd "$BASE_DIR/$src" && find . -type f -print0 | sort -z)

    while IFS= read -r -d '' relfile; do
        local src_file="$BASE_DIR/$src/$relfile"
        if [[ ! -f "$src_file" ]]; then
            echo "[NOMES A $dst] $relfile"
            ONLY_IN_TARGET+=("$dst:$relfile")
            diff_found=1
        fi
    done < <(cd "$BASE_DIR/$dst" && find . -type f -print0 | sort -z)

    if [[ "$diff_found" -eq 0 ]]; then
        echo "Cap canvi rellevant detectat."
    fi

    echo
}

print_summary() {
    echo
    echo "================ RESUM ================"

    echo
    echo "Fitxers només a $SOURCE_ENV:"
    if [[ ${#ONLY_IN_SOURCE[@]} -eq 0 ]]; then
        echo "  (cap)"
    else
        printf '  %s\n' "${ONLY_IN_SOURCE[@]}"
    fi

    echo
    echo "Canvis reals detectats:"
    if [[ ${#REAL_CHANGES[@]} -eq 0 ]]; then
        echo "  (cap)"
    else
        printf '  %s\n' "${REAL_CHANGES[@]}"
    fi

    echo
    echo "Fitxers només al target:"
    if [[ ${#ONLY_IN_TARGET[@]} -eq 0 ]]; then
        echo "  (cap)"
    else
        printf '  %s\n' "${ONLY_IN_TARGET[@]}"
    fi

    echo
    echo "=========== CP SUGGERITS ==========="

    if [[ ${#ONLY_IN_SOURCE[@]} -eq 0 && ${#REAL_CHANGES[@]} -eq 0 ]]; then
        echo "No hi ha fitxers per propagar."
        return
    fi

    for item in "${ONLY_IN_SOURCE[@]}" "${REAL_CHANGES[@]}"; do
        [[ -z "${item:-}" ]] && continue
        local target="${item%%:*}"
        local relfile="${item#*:}"

        local target_dir
        target_dir="$(dirname "$BASE_DIR/$target/$relfile")"

        echo "mkdir -p \"$target_dir\""
        echo "cp \"$BASE_DIR/$SOURCE_ENV/$relfile\" \"$BASE_DIR/$target/$relfile\""
    done
}

for target in "${TARGET_ENVS[@]}"; do
    compare_envs "$SOURCE_ENV" "$target"
done

print_summary