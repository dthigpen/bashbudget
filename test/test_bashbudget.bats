#!/usr/bin/env bats

function setup {
	export PATH="${BATS_TEST_DIRNAME}/../bin/:${PATH}"
}
@test "show usage on help" {
	run bashbudget -h
	[ "${status}" -eq 0 ]
	[[ "${output}" == *'Usage: bashbudget'* ]]
	run "${BATS_TEST_DIRNAME}"/../bin/bashbudget --help
	[ "${status}" -eq 0 ]
	[[ "${output}" == *'Usage: bashbudget'* ]]
}

@test "show no arguments message" {
	run "${BATS_TEST_DIRNAME}"/../bin/bashbudget
	[ "${status}" -ne 0 ]
	[[ "${output}" == *'Must provide at least one command'* ]]
}
