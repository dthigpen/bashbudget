#!/usr/bin/env bats

function setup {
	source "${BATS_TEST_DIRNAME}"/../bin/bashbudget
	# Create a temp ini file for testing
  	ini_file="$BATS_TEST_TMPDIR/test.ini"
}

teardown() {
  rm -f "$ini_file"
}

@test "parse_ini sets config_var with a simple key-value" {
  echo "date_column=Date" > "$ini_file"
  declare -A config_var=()
  parse_ini "$ini_file" config_var
  # echo "config ${config_var[*]}"
  [ "${config_var[date_column]}" = "Date" ]
}

@test "parse_ini trims whitespace around keys and values" {
  skip "ini parser does not do this right now"
  echo "  amount_column   =   Amount  " > "$ini_file"
  declare -A config_var=()
  parse_ini "$ini_file" config_var
  [ "${config_var[amount_column]}" = "Amount" ]
}

@test "parse_ini ignores comments and blank lines" {
  echo -e "# Comment line\n\naccount=Checking" > "$ini_file"
  declare -A config_var=()
  parse_ini "$ini_file" config_var
  [ "${config_var[account]}" = "Checking" ]
  [ "${config_var[#]}" = "" ]  # Ensure no junk key
  [ "${#config_var[@]}" -eq 1 ]  # Ensure no extra keys
}

@test "parse_ini handles multiple keys" {
  cat > "$ini_file" <<EOF
date_column=Date
desc_column=Description
amount_column=Amount
EOF
  declare -A config_var=()
  parse_ini "$ini_file" config_var
  [ "${config_var[date_column]}" = "Date" ]
  [ "${config_var[desc_column]}" = "Description" ]
  [ "${config_var[amount_column]}" = "Amount" ]
}

@test "parse_ini skips invalid lines (no = sign)" {
  echo "this_line_is_invalid" > "$ini_file"
  declare -A config_var=()
  parse_ini "$ini_file" config_var || code=$?
  [ "${code}" -eq 1 ]
  [ "${#config_var[@]}" -eq 0 ]
}
