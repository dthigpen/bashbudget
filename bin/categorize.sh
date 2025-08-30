#!/usr/bin/env bash
set -euo pipefail
set -x
REF_FILES=()
SUGGEST=false
INTERACTIVE=false
INPUT="-"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [INPUT.csv]

Categorize transactions with optional references.

Options:
  --ref FILES...       One or more categorized .csv files to use as references.
                       All consecutive .csv args after --ref will be gathered.
  --suggest            Enable category suggestion (stub for now).
  -i, --interactive    Prompt for user input on uncategorized rows.
  -h, --help           Show this help.

If INPUT is not provided, stdin is used.
Output is written to stdout.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ref)
                shift
                while [[ $# -gt 0 && "$1" == *.csv ]]; do
                    REF_FILES+=("$1")
                    shift
                done
                continue
                ;;
            --suggest)
                SUGGEST=true
                ;;
            -i|--interactive)
                INTERACTIVE=true
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                echo "Unknown option: $1" >&2
                usage >&2
                exit 1
                ;;
            *)
                if [[ "$INPUT" = "-" ]]; then
                    INPUT="$1"
                else
                    echo "Too many inputs (only one INPUT.csv allowed)" >&2
                    exit 1
                fi
                ;;
        esac
        shift
    done
}

load_references() {
    REF_TEMP=$(mktemp)
    if [[ ${#REF_FILES[@]} -gt 0 ]]; then
        mlr --csv cat "${REF_FILES[@]}" > "$REF_TEMP"
    else
        # empty file with just header for safe use
        echo "date,description,amount,account,category" > "$REF_TEMP"
    fi
}

suggest_category() {
    # Placeholder for future suggestion logic
    # Params: date desc amount account
    echo ""
}

function msg {
  echo >&2 -e "${@}"
}

# Lookup category by exact (date, amount, account, description) match in REF_TEMP.
# Usage: matched=$(lookup_category "$date" "$desc" "$amount" "$account")
lookup_category() {
    local q_date="$1"
    local q_desc="$2"
    local q_amount="$3"
    local q_account="$4"
    # in case the caller passed extra args, ignore them
    shift 4 || true

    # REF_TEMP is created by load_references()
    if [[ -z "${REF_TEMP:-}" || ! -s "${REF_TEMP}" ]]; then
        echo ""
        return 0
    fi

    # Use env vars inside Miller to avoid shell-quoting issues
    QDATE="$q_date" QDESC="$q_desc" QAMOUNT="$q_amount" QACCOUNT="$q_account" \
    mlr --csv filter '
        $date == ENV["QDATE"] &&
        $description == ENV["QDESC"] &&
        $amount == ENV["QAMOUNT"] &&
        $account == ENV["QACCOUNT"]
    ' then cut -f category "${REF_TEMP}" 2>/dev/null \
    | tail -n +2 | head -n 1
}

process_transactions() {
    local input="$1"
    local ref_files=("${@:2}")

    # If input is -, save stdin to a temp file so we don't "steal" it
    if [[ "$input" == "-" ]]; then
        local tmp_in=''
        tmp_in=$(mktemp)
        cat > "$tmp_in"
        input="$tmp_in"
    fi

    # Build Miller command
    local mlr_cmd=("mlr" "--csv" "cat" "$input")

    # Use process substitution to feed loop
    while IFS=, read -r date desc amount account category rest; do
        if [[ -z "$category" ]]; then
            category=$(lookup_category "$date" "$desc" "$amount" "$account" "${ref_files[@]}")
			if [[ "$INTERACTIVE" == true ]]; then
			    # Pre-populate prompt with suggestion if present
			    prompt="Enter category"
			    [[ -n "${suggested:-}" ]] && prompt+=" [${suggested}]"
			    prompt+=": "
			
			    # Read from the terminal instead of stdin
			    read -r -p "$prompt" user_input < /dev/tty
			
			    if [[ -n "$user_input" ]]; then
			        category="$user_input"
			    elif [[ -n "$suggested" ]]; then
			        category="$suggested"
			    else
			        category=""
			    fi
			fi
        fi

        echo "$date,$desc,$amount,$account,$category${rest:+,$rest}"
    done < <("${mlr_cmd[@]}")

    # cleanup temp file if stdin was captured
    [[ -n "${tmp_in:-}" ]] && rm -f "$tmp_in"
}

main() {
    parse_args "$@"
    load_references
    process_transactions "${INPUT}"
    rm -f "$REF_TEMP"
}

main "$@"
