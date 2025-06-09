#!/usr/bin/env bats

@test "show usage on help" {
	run "${BATS_TEST_DIRNAME}"/../bin/bashbudget -h
	[ "${status}" -eq 0 ]
	[[ "${output}" == *'Usage: bashbudget'* ]]
	run "${BATS_TEST_DIRNAME}"/../bin/bashbudget --help
	[ "${status}" -eq 0 ]
	[[ "${output}" == *'Usage: bashbudget'* ]]
}

@test "show not enough arguments msg" {
	run "${BATS_TEST_DIRNAME}"/../bin/bashbudget
	[ "${status}" -ne 0 ]
	[[ "${output}" == *'Must provide more arguments'* ]]
}
