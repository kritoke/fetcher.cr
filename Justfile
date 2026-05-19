# Justfile: helper recipes for managing the Public Suffix List (PSL)
#
# Recipes:
#  - just psl-update            # fetch new PSL and replace bundled file (safe/atomic)
#  - just psl-version           # show VERSION and COMMIT in bundled file
#  - just psl-backup            # copy current bundled file to a timestamped backup
#  - just psl-verify FILE=...   # basic validation of a PSL file (default: bundled file)
#  - just psl-diff              # show git diff or diff against last backup
#  - just psl-commit            # git-add + commit the updated PSL (if changes)
#  - just psl-update-commit    # update, and commit if changed

# Default path to the bundled PSL
PSL_PATH := "src/fetcher/public_suffix_list.dat"

# Backup current PSL (creates backups/ with timestamped copies)
psl-backup:
	@set -e; \
	if [ -f "{{PSL_PATH}}" ]; then \
	  mkdir -p .psl-backups; \
	  ts=$(date -u +"%Y%m%dT%H%M%SZ"); \
	  cp "{{PSL_PATH}}" ".psl-backups/public_suffix_list.${ts}.dat"; \
	  echo "Backed up {{PSL_PATH}} -> .psl-backups/public_suffix_list.${ts}.dat"; \
	else \
	  echo "No existing {{PSL_PATH}} to backup"; \
	fi

# Basic validation of a PSL file. Usage: just psl-verify FILE=path/to/file
psl-verify:
	@FILE=${FILE:-{{PSL_PATH}}}; \
	set -e; \
	if [ ! -f "$${FILE}" ]; then \
	  echo "PSL file not found: $${FILE}" >&2; exit 1; \
	fi; \
	# Must contain VERSION and at least one non-comment entry
	grep -m1 '^// VERSION:' "$${FILE}" >/dev/null || { echo "No VERSION header found in $${FILE}" >&2; exit 1; }; \
	# simple heuristic: find a non-empty, non-comment line
	awk 'BEGIN{ok=0} /^\s*\/\//{next} /^\s*$$/{next} {ok=1; exit} END{if(ok==1) exit 0; else exit 1}' "$${FILE}" || { echo "PSL appears empty (no rules) in $${FILE}" >&2; exit 1; }; \
	echo "PSL $${FILE} looks valid"

# Download the latest PSL to a temp file, verify it, backup current, and atomically install.
psl-update:
	@set -e; \
	TMP_DIR=$$(mktemp -d 2>/dev/null || mktemp -d -t psl); \
	TMP_FILE="$${TMP_DIR}/public_suffix_list.dat"; \
	echo "Downloading public_suffix_list.dat to $${TMP_FILE}..."; \
	curl -fSL https://publicsuffix.org/list/public_suffix_list.dat -o "$${TMP_FILE}"; \
	# verify downloaded file
	just psl-verify FILE="$${TMP_FILE}"; \
	# backup existing
	if [ -f "{{PSL_PATH}}" ]; then \
	  just psl-backup; \
	fi; \
	# install atomically
	mv "$${TMP_FILE}" "{{PSL_PATH}}"; \
	rmdir "$${TMP_DIR}" || true; \
	echo "Installed new PSL to {{PSL_PATH}}"; \
	just psl-version

# Show the bundled PSL version and commit (if present)
psl-version:
	@grep -m1 '^// VERSION:' {{PSL_PATH}} 2>/dev/null || echo 'VERSION: (not found)'; \
	grep -m1 '^// COMMIT:' {{PSL_PATH}} 2>/dev/null || echo 'COMMIT: (not found)'

# Show git diff for the PSL file if in a git repo; otherwise diff against the most recent backup
psl-diff:
	@set -e; \
	if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
	  git --no-pager diff -- {{PSL_PATH}} || true; \
	else \
	  LATEST_BACKUP=$$(ls -1t .psl-backups/public_suffix_list.*.dat 2>/dev/null | head -n1 || true); \
	  if [ -n "$${LATEST_BACKUP}" ]; then \
	    echo "Diff against latest backup: $${LATEST_BACKUP}"; \
	    diff -u "$${LATEST_BACKUP}" {{PSL_PATH}} || true; \
	  else \
	    echo "No git repo and no backups found"; \
	  fi; \
	fi

# If PSL file changed, commit it with a message containing VERSION+COMMIT.
psl-commit:
	@set -e; \
	if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
	  echo "Not in a git repository — cannot commit"; exit 1; \
	fi; \
	if git status --porcelain -- {{PSL_PATH}} | grep -q .; then \
	  ver=$$(grep -m1 '^// VERSION:' {{PSL_PATH}} | sed -e 's/^\/\/ VERSION:\s*//'); \
	  com=$$(grep -m1 '^// COMMIT:' {{PSL_PATH}} | sed -e 's/^\/\/ COMMIT:\s*//'); \
	  git add {{PSL_PATH}}; \
	  git commit -m "Update public_suffix_list.dat: ${ver:-unknown} ${com:-unknown}" || true; \
	  echo "Committed updated {{PSL_PATH}}"; \
	else \
	  echo "No changes to {{PSL_PATH}} to commit"; \
	fi

# Update the PSL and commit if changed
psl-update-commit:
	@set -e; \
	just psl-update; \
	just psl-diff; \
	just psl-commit

# Convenience alias
update-psl: psl-update

# -------------------------
# Development / build tasks
# -------------------------

# Install dependencies (Crystal shards)
deps:
	@echo "Installing shards..."
	@shards install

# Build the CLI/binary to bin/fetcher (requires crystal + shards)
build:
	@echo "Ensuring dependencies..."; \
	shards install >/dev/null 2>&1 || true; \
	echo "Building src/fetcher.cr (release)..."; \
	crystal build src/fetcher.cr --release -o bin/fetcher; \
	echo "Built bin/fetcher"

# Run the built binary (falls back to crystal run when not built)
run:
	@if [ -x ./bin/fetcher ]; then \
	  ./bin/fetcher; \
	else \
	  crystal run src/fetcher.cr; \
	fi

# Run specs. Optionally pass SPEC_ARGS environment variable, e.g. SPEC_ARGS="spec/foo_spec.cr"
spec:
	@shards install >/dev/null 2>&1 || true; \
	crystal spec $${SPEC_ARGS:-}

# Run specs with verbose output (useful for debugging)
spec-verbose:
	@shards install >/dev/null 2>&1 || true; \
	crystal spec --verbose $${SPEC_ARGS:-}

# Format sources (crystal tool format)
format:
	@echo "Formatting src/ and spec/"; \
	crystal tool format src || true; \
	crystal tool format spec || true; \
	echo "Format complete"

# Lint using ameba (development dependency). Run 'shards install' first if ameba not found.
lint:
	@if command -v ameba >/dev/null 2>&1; then \
	  ameba; \
	else \
	  echo "ameba not found. Run 'just deps' to install development deps."; \
	  exit 1; \
	fi

# Clean build artifacts and backups
clean:
	@rm -rf .crystal bin/fetcher .psl-backups || true; \
	echo "Cleaned build artifacts and backups"
