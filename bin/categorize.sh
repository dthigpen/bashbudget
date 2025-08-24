#!/usr/bin/env bash
set -euo pipefail

# Globals
REQUIRED_COLUMNS=("date" "description" "amount" "account" "category")

usage() {
    echo "Usage: $0 <normalized_file.csv> --output <categorized_file.csv> [--suggest] [--interactive]"
    exit 1
}

# Check args
if [[ $# -lt 3 ]]; then
    usage
fi

NORMALIZED_FILE=""
OUTPUT_FILE=""
SUGGEST=0
INTERACTIVE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --suggest)
            SUGGEST=1
            shift
            ;;
        --interactive)
            INTERACTIVE=1
            shift
            ;;
        *)
            if [[ -z "${NORMALIZED_FILE}" ]]; then
                NORMALIZED_FILE="$1"
                shift
            else
                echo "Unknown argument: $1"
                usage
            fi
            ;;
    esac
done

if [[ -z "${NORMALIZED_FILE}" || -z "${OUTPUT_FILE}" ]]; then
    usage
fi

mkdir -p "$(dirname "${OUTPUT_FILE}")"

# ------------------------------------------------------------------------------
# 1. Start with the normalized file
cp "${NORMALIZED_FILE}" "${OUTPUT_FILE}.work"

# ------------------------------------------------------------------------------
# 2. Merge prior categorized data (if it exists)
PRIOR_FILE="${OUTPUT_FILE}"
if [[ -f "${PRIOR_FILE}" ]]; then
    echo "Merging categories from existing ${PRIOR_FILE}..."
    mlr --csv join --ul -j date,description,amount,account \
        -f "${OUTPUT_FILE}.work" \
        then put 'if ((
