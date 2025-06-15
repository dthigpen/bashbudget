#!/usr/bin/env bats

setup() {
	export SCRIPT="${BATS_TEST_DIRNAME}/../bin/bashbudget"
	source "${SCRIPT}"
	export TMPDIR="$BATS_TEST_TMPDIR"
	cd "$TMPDIR" || return 1

	export IMPORT_FILE="$TMPDIR/to_import.csv"
	export IMPORTER_FILE="$TMPDIR/test_importer.ini"
	export CONFIG_FILE="$TMPDIR/config.ini"

  	cat > "$IMPORT_FILE" <<EOF
Transaction Date,Details,Amount
2024-02-01,Cafe,-4.25
2024-02-02,Bookstore,-15.00
EOF
	cat > "${IMPORTER_FILE}" <<EOF
name=test
date_column=Transaction Date
desc_column=Details
amount_column=Amount
account_value=Test Account
EOF
}

teardown() {
	rm -f "$IMPORT_FILE" "$IMPORTER_FILE"
}

@test "read_external_txns parses and transforms imported transactions" {
	run read_external_txns "$IMPORT_FILE" "${IMPORTER_FILE}"
	echo "${output}"
	[ "$status" -eq 0 ]

	# Should have a header and two data rows
	echo "$output" | grep -q '^date,description,amount,account,category$'
	echo "$output" | grep -q '2024-02-01,Cafe,-4.25,Test Account,'
	echo "$output" | grep -q '2024-02-02,Bookstore,-15.00,Test Account,'
}

@test "add_id_column_to_txns adds unique IDs as first column" {
	echo "date,description,amount,account
2024-02-01,Cafe,-4.25,Test Account
2024-02-02,Bookstore,-15.00,Test Account" > txns.csv

	run add_id_column_to_txns 100 < txns.csv
	[ "$status" -eq 0 ]

	# Should have 3 lines: header + 2 rows
	num_lines=$(echo "$output" | wc -l)
	[ "$num_lines" -eq 3 ]

	# Check that the header starts with "id"
	echo "$output" | head -n 1 | grep -q '^id,'

	# Check that IDs are correct
	echo "$output" | grep -q '^100,2024-02-01,Cafe,-4.25,Test Account'
	echo "$output" | grep -q '^101,2024-02-02,Bookstore,-15.00,Test Account'
}
