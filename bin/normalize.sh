#!/usr/bin/env bash
set -euo pipefail

# Globals
REQUIRED_COLUMNS=("date" "description" "amount" "account")
OPTIONAL_COLUMNS=("category" "notes")
ALL_COLUMNS=("date" "description" "amount" "account" "category")
INPUT_FILES=()
OUTPUT_FILE=''
IMPORTER_FILES=()
DRY_RUN=false

usage() {
    echo "Usage: $0 <input1.csv> <input2.csv> --importers <ini-file> --output <csv-file> [--dry-run]"
    exit 1
}


function msg {
  echo >&2 -e "${@}"
}

function parse_args() {
	
	# Parse args
	while [[ $# -gt 0 ]]; do
	    case "$1" in
	        -o|--output)
	            OUTPUT_FILE="$2"
	            shift 2
	            ;;
	        --importers)
	        	shift
	        	while [[ $# -gt 0 ]] && [[ "$1" == *.ini  ]]; do
	            	IMPORTER_FILES+=("$1")
	            	shift
	        	done
	            ;;
	        --dry-run)
	            DRY_RUN='true'
	            shift
	            ;;
            -h|--help)
            	usage
            	;;
           	-v|--verbose)
           		set -x
           		shift
           		;;
			-*)
	            echo "Unknown argument: $1"
	            usage
	            ;;
	        *)
	        	INPUT_FILES+=("$1")
	        	shift
	        	;;
	    esac
	done

	if [[ ${#IMPORTER_FILES[@]} -eq 0 ]]; then
		msg "Must provide at least one importer path. e.g --importers bank1-importer.ini"
		exit 1
	fi
}

function setup_fds() {
	# decide input source: files vs stdin
	if [[ ${#INPUT_FILES[@]} -eq 0 ]]; then
		# No files given -> stdin, otherwise use INPUT_FILES later
		exec 3<&0
	fi

	# decide output: file vs stdout
	if [[ -n "${OUTPUT_FILE}" ]]; then
		exec 4>"${OUTPUT_FILE}"
	else
		exec 4>&1
	fi
}

validate_and_pass() {
    local header_read=false
    while IFS= read -r line; do
        if ! $header_read; then
            # Always pass through header line
            echo "$line"
            header_read=true
            continue
        fi

        # Extract first field (up to comma)
        local first_field=${line%%,*}

        # Validate YYYY-MM-DD
        if [[ "$first_field" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            echo "$line"
        else
            echo "Error: invalid date '$first_field'" >&2
            exit 1
        fi
    done
}

function debug_pass() {
	while IFS= read -r line; do
		msg "DEBUG: ${line}"
		echo "${line}"
	done
}
function process_input() {
	local importer=''
	if (( ${#IMPORTER_FILES[@]} == 1 )); then
		importer="${IMPORTER_FILES[0]}"
	else
		importer="$(match_importer "${f}")" || {
	        msg "No matching importer found for ${f}"
	        exit 1
	    }
		# read importer
	    declare -A IMPORTER_CONFIG=()
	    parse_ini "${importer}" IMPORTER_CONFIG
	fi
	msg "Using importer ${importer}"
    # Load external txns
   	# Transform: rename fields, filter out extras, add fields, reorder
   	mlr --csv cat |
   	rename_txn_fields IMPORTER_CONFIG |
   	inject_constant_fields IMPORTER_CONFIG |
   	format_date IMPORTER_CONFIG |
   	filter_relevant_columns |
   	add_optional_columns_to_txns |
   	reorder_txn_fields |
   	debug_pass |
   	validate_and_pass
    
}
function run() {
	if [[ ${#INPUT_FILES[@]} -eq 0 ]]; then
		# stdin mode
		process_input >&4
	else
		local first=1
		for f in "${INPUT_FILES[@]}"; do
			msg "Processing: $f"
			if [[ $first -eq 1 ]]; then
				# cat "${f}" | process_input
				process_input < "${f}" >&4
				first=0
			else
				# cat "${f}" | process_input | tail -n +2
				process_input < "${f}" | tail -n +2 >&4
			fi
		done
	fi
}


# ------------------------------------------------------------------------------
# Parse an importer.ini into an associative array
parse_ini() {
    local file="$1"
    declare -n out="$2"
    while IFS='=' read -r key value; do
        [[ -z "${key}" || "${key}" =~ '^\s*[#;]' ]] && continue
        out["${key}"]="${value}"
    done < "${file}"
}

# Try to match a CSV to an importer.ini
match_importer() {
    local csv_file="$1"
    local header
    header=$(head -n 1 "${csv_file}" | tr -d '\r')

    for ini in "${IMPORTER_FILES[@]}"; do
        declare -A cfg=()
        parse_ini "${ini}" cfg
        if [[ -n "${cfg[match_header]-}" ]]; then
            if [[ "${header}" == "${cfg[match_header]}" ]]; then
                echo "${ini}"
                return 0
            fi
        elif [[ -n "${cfg[match_header_pattern]-}" ]]; then
            if [[ "${header}" =~ ${cfg[match_header_pattern]} ]]; then
                echo "${ini}"
                return 0
            fi
		elif [[ -n "${cfg[match_file_name_pattern]-}" ]]; then
			# TODO resolve to full path so user can match on subdir?
            if [[ "${csv_file}" =~ ${cfg[match_file_name_pattern]} ]]; then
                echo "${ini}"
                return 0
            fi
        fi
    done

    return 1
}


function join_args {
	local IFS="${1}"
	shift
	echo "$*"
}


function rename_txn_fields {
	local -n config="$1"
	local rename_args=""

	for key in "${!config[@]}"; do
		if [[ "$key" == *_column ]]; then
			local newname="${key%_column}"
			local oldname="${config[$key]}"
			if [[ "${newname}" == 'desc' ]]
			then
				newname='description'
			fi
			if [[ "${oldname}" == "${newname}" ]]
			then
				continue
			fi
	     	rename_args+="${oldname},${newname},"
	   fi
	done
	rename_args="${rename_args%,}"
	if [[ -n "$rename_args" ]]; then
		mlr --csv rename "$rename_args"
	else
		cat
	fi
}

function format_date {
  local -n config="$1"
  local fmt="${config[date_format]-}"

  if [[ -n "$fmt" ]]; then
    # Allow strftime-style strings directly in .ini
    local strftime_fmt="$fmt"

    mlr --csv put "\$date=strftime(strptime(\$date,\"$strftime_fmt\"),\"%Y-%m-%d\")"

  else
  # # 	# TODO fix exit(1) not being found
  # 	mlr --csv put '
  # 	  if (is_null($date) || $date == "" || !($date =~ "^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) {
  # 	    eprint "Error: non-ISO date (either use ISO or add something like date_format=%m/%d/%Y to your importer .ini): " . $date;
  # 	    exit(1);
  # 	  }
  # 	' || { msg "ERROR: $?"; exit 1; }
  	cat
  fi
  # cat
  #   # No date_format provided: enforce ISO strictly
}

function inject_constant_fields {
  local -n config="$1"
  local put_exprs=()

  for key in "${!config[@]}"; do
    if [[ "$key" == *_value ]]; then
      local field="${key%_value}"
      local value="${config[$key]}"
      put_exprs+=("\$$field=\"$value\"")
    fi
  done

  if (( ${#put_exprs[@]} )); then
    local put_chain
    put_chain=$(IFS='; '; echo "${put_exprs[*]}")
    mlr --csv put "$put_chain"
  else
    cat
  fi
}

function filter_relevant_columns {
	local columns="$(join_args , "${ALL_COLUMNS[@]}")"
	mlr --csv cut -f "${columns}" 'then' 'cat'
}

function add_optional_columns_to_txns {
	local putexprs=()
	for col in "${OPTIONAL_COLUMNS[@]}"
	do
		put_exprs+=("if (!haskey(\$*, \"$col\")) { \$$col = \"\"}")
	done
	local put_chain
	put_chain=$(IFS='; '; echo "${put_exprs[*]}")
	mlr --csv put "${put_chain}"
	
}

function reorder_txn_fields {
	local fields
	fields=$(IFS=','; echo "${ALL_COLUMNS[@]}")
	mlr --csv reorder -f "${fields}"
}


parse_args "${@}"
setup_fds
run

