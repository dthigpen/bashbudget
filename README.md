# bashbudget

**bashbudget** is a lightweight command-line tool for managing personal finance data using Bash and CSV files. It emphasizes portability, transparency, and Unix-style composability — ideal for those who prefer simple, scriptable workflows over complex GUI software.

**NOTE**: This is a work in progress. Stay tuned for more!

## Features

- Import and normalize transactions from different CSV formats
- Automatically rename and enrich fields using configurable importers
- Filter, edit, and summarize transactions with Miller (`mlr`)
- Built-in validation to ensure data consistency
- Simple file-based "database" that works well with version control

## Requirements

- Bash (>= 4.0 for associative arrays)
- [`mlr`](https://miller.readthedocs.io/) (Miller 6+ recommended)

Development dependencies
- [`shellcheck`](https://www.shellcheck.net/) (optional, for linting)
- [`bats`](https://github.com/bats-core/bats-core) (optional, for testing)

## 🔧 Installation

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

## Usage

Here’s a simple (future) usage example to import a CSV file using a named importer config:

```
bashbudget transactions import my_txns.csv --importer chase_card
```

Then generate a category summary:

```
bashbudget reports totals --from 2024-01-01 --to 2024-06-01
```

## Project Goals

- Composable: Pipes in, pipes out — works well in scripts
- Minimal: No databases or dependencies beyond Miller and Bash
- Transparent: Easy to inspect, modify, or audit your data
- Git-friendly: Your finance data lives in plain text
