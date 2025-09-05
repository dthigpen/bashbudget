#!/usr/bin/env bash
set -euo pipefail

# Globals
ALL_COLUMNS=("date" "description" "amount" "account" "category" "notes" "id")
INPUT_FILES=()
OUTPUT_FILE='-'
IMPORTER_FILES=()

usage() {
    echo "Usage: $0 <input1.csv> <input2.csv> --importers <ini-file> --output <csv-file>"
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

# importers array is passed by name; e.g. match_importer IMPORTER_FILES
match_importer_and_normalize() {
    local -n _importers="$1"
	local filename="${2-}"

    # Read first line (header) from stdin
    local header
    if ! IFS= read -r header; then
        echo "ERROR: empty input (no header)" >&2
        return 1
    fi
    # Strip possible BOM and CR
    # BOM: 0xEF 0xBB 0xBF
    header="${header#"$'\xEF\xBB\xBF'"}"
    header="${header%$'\r'}"

    # Auto-pick if only one importer
    local chosen=""
    if [[ ${#_importers[@]} -eq 1 ]]; then
        chosen="${_importers[0]}"
    else
        # Try each ini
        local ini mh mhp
        for ini in "${_importers[@]}"; do
            # Read keys (allow missing)
            mh="$(sed -n 's/^[[:space:]]*match_header[[:space:]]*=[[:space:]]*//p' "${ini}" | head -n1 || true)"
            mhp="$(sed -n 's/^[[:space:]]*match_header_pattern[[:space:]]*=[[:space:]]*//p' "${ini}" | head -n1 || true)"
            mfnp="$(sed -n 's/^[[:space:]]*match_file_name_pattern[[:space:]]*=[[:space:]]*//p' "${ini}" | head -n1 || true)"

            # Exact match first
            if [[ -n "${mh}" && "${header}" == "${mh}" ]]; then
                chosen="${ini}"
                break
            fi
            # Regex match (unquoted on RHS by design for [[ =~ ]])
            if [[ -n "${mhp}" && "${header}" =~ ${mhp} ]]; then
                chosen="${ini}"
                break
            fi

            if [[ -n "${mfnp}" ]]; then
				if [[ -z "${filename}" || "${filename}" == '-' ]]; then
					msg "Warning: Importer ${ini} has a file name match rule but piped in content has no filename"
				fi
	            # Regex match (unquoted on RHS by design for [[ =~ ]])
	            if [[ "${filename}" =~ ${mfnp} ]]; then
	                chosen="${ini}"
	                break
	            fi
            fi
        done
    fi

    if [[ -z "${chosen}" ]]; then
        {
            echo "ERROR: no matching importer for header:"
            printf '  header: %q\n' "${header}"
        } >&2
        return 1
    fi

    # Optional debug
    # echo "INFO: matched importer: ${chosen}" >&2

    # Emit metadata + original stream
    # echo "#importer=${chosen}"
    {
	    echo "${header}"
	    cat
    } | normalize_stream "${chosen}"
}

normalize_stream() {
    local importer="$1"
    local line=''
    local count=0
	
    	# msg "DT_DEBUG here ${line} ${importer} ${count}"
    if [[ -z "${importer}" ]]; then
        echo "ERROR: no importer specified in input stream (missing #importer=… line)" >&2
        exit 1
    fi

    # --- Your existing normalize steps go here ---
    # Example scaffold using your INI to build args:
    declare -A IMPORTER_CONFIG=()
    parse_ini "${importer}" IMPORTER_CONFIG

    # Transform: rename fields, filter out extras, add fields, reorder
   	mlr --csv cat |
   	rename_txn_fields IMPORTER_CONFIG |
   	inject_constant_fields IMPORTER_CONFIG |
   	format_date IMPORTER_CONFIG |
   	filter_relevant_columns |
   	add_missing_columns_to_txns |
   	add_hash_id |
   	reorder_txn_fields |
   	# debug_pass |
   	validate_and_pass
    # }
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

function add_missing_columns_to_txns {
	local putexprs=()
	for col in "${ALL_COLUMNS[@]}"
	do
		put_exprs+=("if (!haskey(\$*, \"$col\")) { \$$col = \"\"}")
	done
	local put_chain
	put_chain=$(IFS='; '; echo "${put_exprs[*]}")
	mlr --csv put "${put_chain}"
}

function add_hash_id {
	mlr --csv put '
      $id = substr(sha1($date . "|" . $amount . "|" . $account . "|" . $description), 1, 10)
    '
}

function reorder_txn_fields {
	local fields
	fields=$(IFS=','; echo "${ALL_COLUMNS[@]}")
	mlr --csv reorder -f "${fields}"
}

function run_pipeline() {
    local infile="$1"
    if [[ "${infile}" == "-" ]]; then
        match_importer_and_normalize IMPORTER_FILES "${infile}"
    else
        match_importer_and_normalize IMPORTER_FILES "${infile}" < "${infile}"
    fi
}

function run() {
    if [[ "${OUTPUT_FILE}" == "-" ]]; then
        exec 4>&1   # FD 4 → stdout
    else
        exec 4> "${OUTPUT_FILE}"   # FD 4 → file
    fi

    if [[ ${#INPUT_FILES[@]} -eq 0 ]]; then
        run_pipeline "-" >&4
    else
        local first=1
        for f in "${INPUT_FILES[@]}"; do
            if [[ $first -eq 1 ]]; then
            	run_pipeline "${f}" >&4
            else
            	run_pipeline "${f}" | tail -n +2 >&4
            fi
            first=0
        done
    fi
}

parse_args "${@}"
# setup_fds
run

