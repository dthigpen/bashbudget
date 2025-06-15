#!/usr/bin/env bats

setup() {
	export PATH="${BATS_TEST_DIRNAME}"/../bin:"${PATH}"
	# export BB_SCRIPT="$BATS_TEST_DIRNAME/../bashbudget.sh"
	export TMPDIR="$BATS_TEST_TMPDIR"
	export TXNS_FILE="$TMPDIR/bashbudget_txns.csv"
	export IMPORT_FILE="$TMPDIR/to_import.csv"
	export IMPORTER_FILE="$TMPDIR/test_importer.ini"
	cd "$TMPDIR" || return 1

	# Create a sample importer config
	cat > "$IMPORTER_FILE" <<EOF
name=test
date_column=Transaction Date
desc_column=Details
amount_column=Amount
account_value=Test Account
EOF

  # Create a sample import CSV
  cat > "$IMPORT_FILE" <<EOF
Transaction Date,Details,Amount
2024-01-01,Coffee,-3.50
2024-01-02,Grocery,-20.00
EOF
}

teardown() {
  rm -f "$TXNS_FILE" "$IMPORT_FILE" "$IMPORTER_FILE"
}

@test "import creates and appends to bashbudget_txns.csv" {
  run bashbudget import "$IMPORT_FILE" --importer "$IMPORTER_FILE"
  [ "$status" -eq 0 ]
  [ -f "$TXNS_FILE" ]

  # Should have header + 2 rows
  run wc -l "$TXNS_FILE"
  [[ "$output" =~ ^3[[:space:]] ]]
  echo $output
  # Check header has id and renamed fields
  head -n 1 "$TXNS_FILE" | grep -q 'id,date,description,amount,account,category'

  # Check that IDs are added and values match expected
  tail -n +2 "$TXNS_FILE" | while IFS=',' read -r id date desc amount account; do
    [[ "$id" =~ ^[0-9]+$ ]]
    [[ "$account" == "Test Account" ]]
  done
}
