#!/usr/bin/env bash
set -euo pipefail

# ========================
# Globals / Config
# ========================
OUTPUT_FORMAT='txt'
OUTPUT_FILE=""
BUDGET_FILE=""
TRANSACTION_FILES=()

# ========================
# Functions
# ========================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b|--budget)
                BUDGET_FILE="$2"
                shift 2
                ;;
            -t|--transactions)
                while [[ $# -gt 1 && "$2" != -* ]]; do
                    TRANSACTION_FILES+=("$2")
                    shift
                done
                shift
                ;;
            -f|--format)
				OUTPUT_FORMAT="$2"
				shift 2
            	;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                exit 1
                ;;
        esac
    done

    if [[ -z "${BUDGET_FILE}" ]]; then
        echo "Error: --budget is required" >&2
        exit 1
    fi
    if [[ ${#TRANSACTION_FILES[@]} -eq 0 ]]; then
        echo "Error: --transactions requires at least one file" >&2
        exit 1
    fi
    if [[ "${OUTPUT_FORMAT}" != 'txt' &&  "${OUTPUT_FORMAT}" != 'csv' ]]; then
        echo "Error: --format must be followed by either csv or txt" >&2
        exit 1
    fi
}

# Extract period directly from the budget CSV (first data row)
get_period() {
    mlr --csv cut -f period "${BUDGET_FILE}" | mlr --csv skip-trivial-records then head -n 1
}

# Aggregate transactions by category
aggregate_transactions() {
    mlr --csv --implicit-csv-header \
        filter 'is_not_null($category) && $category != ""' \
        then stats1 -a sum -f amount -g category \
        "${TRANSACTION_FILES[@]}"
}

# Join budget with actuals
join_budget_with_actuals() {
    local period="$1"

    mlr --csv join --ul -j name \
        -f <(mlr --csv cut -f name,budget,type,balance,goal,reconcile_amount,override_actual,notes "${BUDGET_FILE}") \
        -f <(aggregate_transactions | mlr --csv cut -f category,sum_amount then rename category,name,sum_amount,actual) \
    | mlr --csv put '
        $period = "'"$period"'";
        $actual = if(is_not_null($override_actual) && $override_actual != "", $override_actual, $actual);
        $variance = if(is_not_null($budget) && $budget != "", $actual - $budget, "");
    '
}

# Compute summary rows (income, expenses, etc.)
compute_summary() {
    local period="$1"

    join_budget_with_actuals "$period" \
    | mlr --csv tee >(mlr --csv filter '$type=="income"' then stats1 -a sum -f budget,actual,variance | mlr --csv put '$section="summary";$name="Income";$period="'"$period"'"') \
           >(mlr --csv filter '$type=="expense"' then stats1 -a sum -f budget,actual,variance | mlr --csv put '$section="summary";$name="Expenses";$period="'"$period"'"') \
           >(mlr --csv filter '$type=="fund"' then cut -f period,type,name,budget,actual,variance,balance,goal,reconcile_amount,notes | mlr --csv put '$section="fund";$start_balance=$balance;$end_balance=$balance+$reconcile_amount') \
    | mlr --csv cut -f period,type,name,budget,actual,variance,balance,goal,reconcile_amount,notes \
    | mlr --csv put '$section="category"' \
    ;
}

write_pretty_report() {
    local csv_file="$1"
    local txt_file="$2"

    {
        echo "=============================="
        echo "   Budget Report: $(mlr --csv cut -f period "$csv_file" | mlr --csv skip-trivial-records then head -n 1)"
        echo "=============================="
        echo

        echo "== Summary =="
        mlr --icsv --opprint filter '$section=="summary"' "$csv_file"
        echo

        echo "== Categories =="
        mlr --icsv --opprint filter '$section=="category"' "$csv_file"
        echo

        echo "== Funds =="
        mlr --icsv --opprint filter '$section=="fund"' "$csv_file"
        echo
    } > "$txt_file"
}
# Main
main() {
    parse_args "$@"
    local period
    period=$(get_period)

    local tmp_out
    tmp_out=$(mktemp)

    compute_summary "$period" > "$tmp_out"

    # Append summary aggregates (cash flow, under/over budget, etc.)
    mlr --csv stats1 -a sum -f budget,actual,variance -g type "$tmp_out" > "$tmp_out.sums"

    local income actual_income expense actual_expense variance_expense
    income=$(mlr --c2n filter '$type=="income"' then cut -f actual "$tmp_out.sums")
    expense=$(mlr --c2n filter '$type=="expense"' then cut -f actual "$tmp_out.sums")
    variance_expense=$(mlr --c2n filter '$type=="expense"' then cut -f variance "$tmp_out.sums")

    cash_flow=$(( income - expense ))
    under_budget=$(( variance_expense > 0 ? variance_expense : 0 ))
    over_budget=$(( variance_expense < 0 ? variance_expense : 0 ))
    net_variance=$(( under_budget + over_budget ))

	{
        echo "period,section,name,budget,actual,variance,start_balance,end_balance,goal,reconcile_amount,notes"
        cat "$tmp_out"
        echo "$period,summary,Cash flow,,${cash_flow},,,,,,"
        echo "$period,summary,Under budget,,${under_budget},,,,,,"
        echo "$period,summary,Over budget,,${over_budget},,,,,,"
        echo "$period,summary,Net variance,,${net_variance},,,,,,"
    } > "$tmp_out.report.csv"
    if [[ "${OUTPUT_FORMAT}" == 'csv' ]]; then
	     cat "$tmp_out.report.csv" > "${OUTPUT_FILE:-/dev/stdout}"
	elif [[ "${OUTPUT_FORMAT}" == 'txt' ]]; then
			write_pretty_report "$tmp_out.report.csv" "$tmp_out.report.txt"
			cat "$tmp_out.report.txt" > "${OUTPUT_FILE:-/dev/stdout}"
    fi

    rm -f "$tmp_out" "$tmp_out".*
}

main "$@"
