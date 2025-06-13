#!/usr/bin/env bats

function setup {
	source "${BATS_TEST_DIRNAME}"/../bin/bashbudget
	# Create a temp ini file for testing
  	ini_file="$BATS_TEST_TMPDIR/test.ini"
}

teardown() {
  rm -f "$ini_file"
}

@test "parse_ini sets INI_CONFIG with a simple key-value" {
  echo "date_column=Date" > "$ini_file"
  parse_ini "$ini_file"
  echo "config ${INI_CONFIG[*]}"
  [ "${INI_CONFIG[date_column]}" = "Date" ]
}

@test "parse_ini trims whitespace around keys and values" {
  skip "ini parser does not do this right now"
  echo "  amount_column   =   Amount  " > "$ini_file"
  parse_ini "$ini_file"
  [ "${INI_CONFIG[amount_column]}" = "Amount" ]
}

@test "parse_ini ignores comments and blank lines" {
  echo -e "# Comment line\n\naccount=Checking" > "$ini_file"
  parse_ini "$ini_file"
  [ "${INI_CONFIG[account]}" = "Checking" ]
  [ "${INI_CONFIG[#]}" = "" ]  # Ensure no junk key
  [ "${#INI_CONFIG[@]}" -eq 1 ]  # Ensure no extra keys
}

@test "parse_ini handles multiple keys" {
  cat > "$ini_file" <<EOF
date_column=Date
desc_column=Description
amount_column=Amount
EOF
  parse_ini "$ini_file"
  [ "${INI_CONFIG[date_column]}" = "Date" ]
  [ "${INI_CONFIG[desc_column]}" = "Description" ]
  [ "${INI_CONFIG[amount_column]}" = "Amount" ]
}

@test "parse_ini skips invalid lines (no = sign)" {
  echo "this_line_is_invalid" > "$ini_file"
  parse_ini "$ini_file" || code=$?
  [ "${code}" -eq 1 ]
  [ "${#INI_CONFIG[@]}" -eq 0 ]
}
