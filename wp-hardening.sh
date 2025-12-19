#!/bin/bash
#
# WordPress Permissions & Hardening Tool
# Safe for cron, SSH, and production use
#

set -euo pipefail

WP_OWNER="www-data"
WP_GROUP="www-data"
WS_GROUP="www-data"

DEFAULT_BASE_PATHS=(
  "/var/www"
  "/var/www/html"
)

BASE_PATHS=("${DEFAULT_BASE_PATHS[@]}")
DRY_RUN=0
ALL_SITES=0
INPUT=""

# -------------------------
# Spinner (TTY only)
# -------------------------

SPINNER_ENABLED=0
[[ -t 1 ]] && SPINNER_ENABLED=1

spinner() {
  local pid=$!
  local msg="$1"
  local delay=0.1
  local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

  if [[ "$SPINNER_ENABLED" -eq 0 ]]; then
    wait "$pid"
    echo "✔ $msg"
    return
  fi

  while ps -p "$pid" > /dev/null 2>&1; do
    for (( i=0; i<${#spinstr}; i++ )); do
      printf "\r%s %s" "$msg" "${spinstr:i:1}"
      sleep "$delay"
    done
  done

  printf "\r%s ✔\n" "$msg"
}

# -------------------------
# Helpers
# -------------------------

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

usage() {
  cat <<EOF
Usage:
  $0 example.com
  $0 /full/path/to/wordpress

Options:
  --dry-run            Show what would be done
  --all-sites          Run on all WordPress sites found
  --base-path=/path    Add custom base path (repeatable)

Examples:
  $0 example.com
  $0 --dry-run example.com
  $0 --all-sites
  $0 --base-path=/srv/www example.com
EOF
  exit 1
}

# -------------------------
# Parse arguments
# -------------------------

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=1
      ;;
    --all-sites)
      ALL_SITES=1
      ;;
    --base-path=*)
      BASE_PATHS+=("${arg#*=}")
      ;;
    -*)
      usage
      ;;
    *)
      INPUT="$arg"
      ;;
  esac
done

[[ "$ALL_SITES" -eq 0 && -z "$INPUT" ]] && usage

# -------------------------
# Find WordPress installs
# -------------------------

discover_sites() {
  local sites=()
  for base in "${BASE_PATHS[@]}"; do
    [[ -d "$base" ]] || continue
    while IFS= read -r -d '' dir; do
      sites+=("$dir")
    done < <(find "$base" -mindepth 1 -maxdepth 2 -type f -name wp-config.php -print0 2>/dev/null)
  done

  for i in "${!sites[@]}"; do
    sites[$i]="$(dirname "${sites[$i]}")"
  done

  printf "%s\n" "${sites[@]}"
}

# -------------------------
# Resolve target sites
# -------------------------

TARGETS=()

if [[ "$ALL_SITES" -eq 1 ]]; then
  mapfile -t TARGETS < <(discover_sites)
  [[ "${#TARGETS[@]}" -eq 0 ]] && { echo "❌ No WordPress sites found"; exit 1; }
else
  if [[ "$INPUT" == /* ]]; then
    TARGETS+=("$INPUT")
  else
    for base in "${BASE_PATHS[@]}"; do
      [[ -d "$base/$INPUT" ]] && TARGETS+=("$base/$INPUT")
    done
  fi
fi

[[ "${#TARGETS[@]}" -eq 0 ]] && { echo "❌ No valid targets found"; exit 1; }

# -------------------------
# Process each site
# -------------------------

for WP_ROOT in "${TARGETS[@]}"; do
  echo
  echo "▶ Processing: $WP_ROOT"

  case "$WP_ROOT" in
    "/"|"/var"|"/var/www"|"/var/www/html")
      echo "❌ Refusing unsafe directory: $WP_ROOT"
      continue
      ;;
  esac

  [[ ! -f "$WP_ROOT/wp-config.php" ]] && { echo "❌ Not WordPress"; continue; }
  [[ ! -d "$WP_ROOT/wp-content" ]] && { echo "❌ Invalid WP install"; continue; }

  # Multisite detection
  if grep -q "MULTISITE.*true" "$WP_ROOT/wp-config.php"; then
    echo "ℹ Multisite detected"
  fi

  (
    run "rm -f \"$WP_ROOT/wp-config-sample.php\" \"$WP_ROOT/config-example.php\""
  ) & spinner "🗑 Removing example config files"

  (
    run "find \"$WP_ROOT\" -exec chown \"$WP_OWNER:$WP_GROUP\" {} \\;"
    run "find \"$WP_ROOT\" -type d -exec chmod 755 {} \\;"
    run "find \"$WP_ROOT\" -type f -exec chmod 644 {} \\;"
  ) & spinner "🔐 Resetting ownership and permissions"

  (
    run "chgrp \"$WS_GROUP\" \"$WP_ROOT/wp-config.php\""
    run "chmod 600 \"$WP_ROOT/wp-config.php\""
  ) & spinner "🔒 Securing wp-config.php"

  (
    run "find \"$WP_ROOT/wp-content\" -exec chgrp \"$WS_GROUP\" {} \\;"
    run "find \"$WP_ROOT/wp-content\" -type d -exec chmod 755 {} \\;"
    run "find \"$WP_ROOT/wp-content\" -type f -exec chmod 664 {} \\;"
  ) & spinner "🧩 Setting wp-content permissions"

  (
    if [[ -f "$WP_ROOT/xmlrpc.php" ]]; then
      run "chmod 000 \"$WP_ROOT/xmlrpc.php\""
    fi
  ) & spinner "🚫 Disabling XML-RPC"

  (
    [[ -f "$WP_ROOT/.htaccess" ]] && run "chmod 644 \"$WP_ROOT/.htaccess\""
  ) & spinner "📄 Securing .htaccess"

  echo "✅ Completed: $WP_ROOT"
done

echo
echo "🎉 All tasks completed."
