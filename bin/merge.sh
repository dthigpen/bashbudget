#!/usr/bin/env bash
set -euo pipefail

print_usage() {
    cat <<EOF
Usage: $0 [OPTIONS] primary.csv [secondary.csv ...]
Options:
  --join COLS        Comma-separated list of columns to join on (optional)
  -o, --output FILE  Write output to FILE (default: stdout)
  -h, --help         Show this message
EOF
}

JOIN_COLS=()
OUTPUT_FILE=""
INPUT_FILES=()

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --join)
                IFS=, read -r -a JOIN_COLS <<< "$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            -*)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
            *)
                INPUT_FILES+=("$1")
                shift
                ;;
        esac
    done

    if [[ ${#INPUT_FILES[@]} -eq 0 ]]; then
        echo "ERROR: Must provide at least one input CSV file" >&2
        exit 1
    fi
}

validate_columns() {
    local primary="${INPUT_FILES[0]}"

    if [[ ${#JOIN_COLS[@]} -eq 0 ]]; then
        return 0 # nothing to validate
    fi

    # validate primary
    IFS=, read -r -a header < <(head -n 1 "$primary")
    declare -A header_map=()
    for col in "${header[@]}"; do header_map["$col"]=1; done

    for col in "${JOIN_COLS[@]}"; do
        if [[ -z "${header_map[$col]:-}" ]]; then
            echo "ERROR: join column '$col' not found in primary file: $primary" >&2
            exit 1
        fi
    done

    # warn for secondary
    for f in "${INPUT_FILES[@]:1}"; do
        IFS=, read -r -a header < <(head -n 1 "$f")
        for col in "${JOIN_COLS[@]}"; do
            if [[ ! " ${header[*]} " =~ " ${col} " ]]; then
                echo "WARNING: join column '$col' not found in secondary file: $f" >&2
            fi
        done
    done
}

build_pipeline() {
    local cmd=()

    if [[ ${#JOIN_COLS[@]} -eq 0 ]]; then
        cmd=(mlr --csv cat "${INPUT_FILES[@]}")
    else
        local primary="${INPUT_FILES[0]}"
        local rest=("${INPUT_FILES[@]:1}")
        local join_cols_str
        join_cols_str="$(IFS=,; echo "${JOIN_COLS[*]}")"

        cmd=(mlr --csv join --lp '' --rp '' --ul -j "$join_cols_str" -f "${INPUT_FILES[@]}")
    fi

    printf '%s\n' "${cmd[@]}"
    
}

main() {
    parse_args "$@"
    validate_columns
    local -a cmd
    mapfile -t cmd < <(build_pipeline)
    if [[ -n "$OUTPUT_FILE" ]]; then
        "${cmd[@]}" > "$OUTPUT_FILE"
    else
        "${cmd[@]}"
    fi
}

main "$@"
