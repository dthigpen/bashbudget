#!/usr/bin/env bash
set -euo pipefail

INPUT_FILES=()
OUTPUT_DIR=''
SPLIT_BY='month'

usage() {
    echo "Usage: $0 [--by day|month|year] --output-dir <dir> [file1.csv ...]"
    exit 1
}

msg() {
    echo >&2 -e "$@"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --by)
                SPLIT_BY="$2"
                shift 2
                ;;
            -o|--output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            -*)
                msg "Unknown option: $1"
                usage
                ;;
            *)
                INPUT_FILES+=("$1")
                shift
                ;;
        esac
    done

    if [[ -z "${OUTPUT_DIR}" ]]; then
        msg "Error: must provide --output-dir"
        usage
    fi
    mkdir -p "${OUTPUT_DIR}"
}

setup_fds() {
    if [[ ${#INPUT_FILES[@]} -eq 0 ]]; then
        exec 3<&0   # stdin fallback
    fi
}

process_all_inputs() {
    local inputs
    if [[ ${#INPUT_FILES[@]} -eq 0 ]]; then
        inputs="/dev/fd/3"
    else
        inputs="${INPUT_FILES[@]}"
    fi

    case "${SPLIT_BY}" in
        day)
            mlr --csv split -g date \
                -o "${OUTPUT_DIR}/%date%-transactions.csv" ${inputs}
            ;;
        month)
			mlr --csv \
			  filter '$date =~ "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"' \
			  then put '$month = substr($date,0,6)' \
			  then split -g month \
			    --prefix "${OUTPUT_DIR%/}/" \
			    --suffix "-transactions.csv" \
			    -j ''
            ;;
        year)
            mlr --csv put '$year = substr($date,0,4)' \
                then split -g year \
                -o "${OUTPUT_DIR}/%year%-transactions.csv" ${inputs}
            ;;
        *)
            msg "Unknown split type: ${SPLIT_BY}"
            exit 1
            ;;
    esac
    for f in "${OUTPUT_DIR}"/*.csv; do
    	mlr --csv \
    		cut -x -f month \
    		then cat \
    		"${f}" > "${f/.-transactions.csv/-transactions.csv}"
    		rm -f "${f}"
    done
}

main() {
    parse_args "$@"
    setup_fds
    process_all_inputs
}

main "$@"
