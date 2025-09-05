#!/usr/bin/env bash
set -euo pipefail
set -x
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
apply_deletes() {
    local primary="$1"
    local secondary="$2"

    # Step 1: collect IDs to delete
    local ids_to_delete
    ids_to_delete=$(mlr --csv filter '
        is_not_empty($id) &&
        (is_empty($date) || $date=="") &&
        (is_empty($amount) || $amount=="") &&
        (is_empty($account) || $account=="") &&
        (is_empty($description) || $description=="") &&
        (is_empty($category) || $category=="") &&
        (is_empty($notes) || $notes=="")
    ' then cut -f id "$secondary")

    # If no deletes, just echo the primary
    if [[ -z "$ids_to_delete" ]]; then
        cat "$primary"
        return
    fi

    # Step 2: remove matching rows from primary
    # Build an mlr filter like: $id!="abc" && $id!="def"
    local delete_expr=""
    while IFS= read -r id; do
        [[ -n "$delete_expr" ]] && delete_expr+=" && "
        delete_expr+="\$id!=\"$id\""
    done <<< "$ids_to_delete"

    mlr --csv filter "$delete_expr" "$primary"
}

apply_updates() {
    local primary="$1"
    local secondary="$2"

    mlr --csv join --ul --ur -j id -f "$primary" "$secondary"
}

apply_adds() {
    local primary="$1"
    local secondary="$2"
	tmp_adds=$(mktemp)
	mlr --csv filter 'is_empty($id)' "$secondary" > "${tmp_adds}"
	head -4 "${primary}" >&2
	cp $primary primary.tmp.txt
	cp $primary secondary.tmp.txt
	cp $tmp_adds adds.tmp.txt
	echo '---' >&2
	head -4 "${tmp_adds}" >&2
    mlr --csv cat "$primary" "${tmp_adds}"
}

check_dangling_ids() {
    local primary="$1"
    local secondary="$2"

    # Anti-join: keep only rows from secondary whose id does not exist in primary
    local dangling
    dangling=$(mlr --csv join -j id -lu -f "$secondary" "$primary")

    if [[ -n "$dangling" ]]; then
        echo "Error: dangling IDs found in '$secondary' that are not in primary:" >&2
        echo "$dangling" >&2
        exit 1
    fi
}

build_pipeline() {
    local primary="${INPUT_FILES[0]}"
    local secondaries=("${INPUT_FILES[@]:1}")

    # Start with the primary file (copy to temp so we never modify original)
    local current
    current=$(mktemp)
    cp "$primary" "$current"

    for sec in "${secondaries[@]}"; do
        # Step 0: check for dangling IDs
        check_dangling_ids "$current" "$sec"

        # Step 1: apply deletes
        local tmp_del
        tmp_del=$(mktemp)
        apply_deletes "$current" "$sec" > "$tmp_del"

        # Step 2: apply updates
        local tmp_upd
        tmp_upd=$(mktemp)
        apply_updates "$tmp_del" "$sec" > "$tmp_upd"

        # Step 3: apply adds (in-place append, careful with headers)
        local tmp_final
        tmp_final=$(mktemp)
        apply_adds "$tmp_upd" "$sec" > "$tmp_final"

        # Advance to next iteration
        current="$tmp_final"
    done

    # Return path to the final file
    echo "$current"
}

main() {
    parse_args "$@"
    validate_columns

    local final_file
    final_file=$(build_pipeline)

    if [[ -n "$OUTPUT_FILE" ]]; then
        cp "$final_file" "$OUTPUT_FILE"
    else
        cat "$final_file"
    fi
}

main "$@"
