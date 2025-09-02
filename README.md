# bashbudget

**bashbudget** is a collection of bash scripts for wrangling financial data and creating a personal budget system. It emphasizes portability, transparency, and Unix-style composability — ideal for those who prefer simple, scriptable workflows over complex GUI software.

**NOTE**: This is undergoing a rewrite, so this README has not been fully updated. Stay tuned for more!

## Features

- `normalize.sh`: Imports all of your various CSV bank transactions into a single normalized CSV format. Useful for further scripting.
- `split.sh`: Splits the given series of CSV transactions into multiple CSVs by day, month, or year.
- `merge.sh`: Combines multiple transactions CSVs into one. Optionally, performs "joins" on given columns. Useful for applying categories to transactions, see example.
- `budget.sh` (Not yet implemented): Takes transactions and a budget file to report monthly spending.

## Requirements

- Bash (>= 4.0 for associative arrays)
- [`mlr`](https://miller.readthedocs.io/) (Miller 6+ recommended)

Development dependencies
- [`shellcheck`](https://www.shellcheck.net/) (optional, for linting)
- [`bats`](https://github.com/bats-core/bats-core) (optional, for testing)

## 🔧 Installation

<!-- 
There is no installation script for now, just download the `bashbudget` script, make it executable, and run it.

### Quick Install with `curl` or `wget`

If you just want to download and run `bashbudget` without cloning the whole repo:

**With `curl`:**

```bash
curl -Lo bashbudget https://raw.githubusercontent.com/dthigpen/bashbudget/main/bin/bashbudget
chmod +x bashbudget
```

**With `wget`:**

```bash
wget -O bashbudget https://raw.githubusercontent.com/dthigpen/bashbudget/main/bin/bashbudget
chmod +x bashbudget
```

Then optionally move it into your PATH:

```bash
# may require sudo (e.g. sudo mv bashbudget /usr/local/bin/)
mv bashbudget /usr/local/bin/
```

### Install with `git`

```sh
git clone https://github.com/dthigpen/bashbudget.git
cd bashbudget
chmod +x bin/bashbudget

# may require sudo (e.g. sudo mv bin/bashbudget /usr/local/bin/)
mv bin/bashbudget /usr/local/bin/
```
-->
## Usage

First, clone the repository or download the scripts in the bin/ directory, then add them to your PATH to make them easily callable.

```sh
$ git clone https://github.com/dthigpen/bashbudget.git
```

```bash
export PATH=~/path/to/bashbudget-clone/bin":${PATH}"

# rest of script (making calls to normalize.sh ..., merge.sh ..., etc.)
```

### `normalize.sh`

Call bashbudget commands within a bash script.

```bash
normalize.sh bank-transactions/*.csv --importers importers/*.ini > normalized-transactions/all-txns.csv
```

Make sure you have an importer for your financial institution already setup. The importer is responsible for identifying your bank's transactions CSV and converting its column names/values to a bashbudget (normalized) format.

```ini
# importers/my-bank-importers.ini

# If this header is found in the bank CSV, then use this importer
match_header=Transaction Date,Post Date,Description,Category,Type,Amount

# Column names mapping
date_column=Transaction Date
description_column=Description
amount_column=Amount

# Set the account value name for all matching rows
account_value=My Credit Card Name
```

### `split.sh`

Splits the given transactions by day, month, or year. Useful for post normalization to break up transactions into smaller, managable files. However this can be done at any point in your process, or not at all.

```
normalize.sh ... | split.sh --by month --output-dir normalized-transactions

ls normalized-transactions/
2025-01-transactions.csv
2025-02-transactions.csv
2025-03-transactions.csv
...
```

### `merge.sh`

Combines multiple transactions CSVs into a single one. By default it acts as the opposite of `split.sh`. If `--join col1,col2,col3,etc` is passed, then a "join" (like a SQL LEFT JOIN) will be applied. Useful to apply modifications to transactions (e.g. adding a category or notes value) without modifying the normalized-transactions themselves.

For example, suppose the bank transactions get imported and normalized with the command below.

```bash
normalize.sh ... | split.sh --by month --output-dir normalized-transaction
```

Now you want to categorize the recent month's transactions so you make a secondary file to hold those categorizations. For example at `categorizations/2025-05-categories.csv`.

```csv
date,description,amount,account,category,notes
2025-05-27,SOUTHWES AIRLINES,243.12,My Credit Card,Travel,Some note here
2025-05-08,COMCAST CABLE COMM,85.37,My Credit Card,Internet,
...
```

These will get merged with the `normalized-transactions`, joining when the columns `date,description,amount,account` are all the same. Thus, the `category` and `note` will get applied.

```bash
merge.sh --join 'date,description,amount,account' normalized-transactions/*.csv categorizations/*.csv > final-transactions/all-final-txns.csv
```

### `budget.sh`

```bash
 # To be written
```

## Project Goals

- Composable: Pipes in, pipes out — works well in scripts
- Minimal: No databases or dependencies beyond Miller and Bash
- Transparent: Easy to inspect, modify, or audit your data
- Git-friendly: Your finance data lives in plain text
