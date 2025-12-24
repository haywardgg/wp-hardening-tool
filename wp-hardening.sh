#!/bin/bash
#
# WordPress Permissions & Hardening Tool
# Safe for cron, SSH, and production use
#

set -euo pipefail

# -------------------------
# Configuration
# -------------------------

WP_OWNER="www-data"
WP_GROUP="www-data"
WS_GROUP="www-data"
WP_CONTENT_DIR_PERMS=755
WP_CONTENT_FILE_PERMS=664
WP_CONFIG_PERMS=600
LOG_FILE="/var/log/wordpress-permissions.log"

DEFAULT_BASE_PATHS=(
  "/var/www"
  "/var/www/html"
  "/srv/www"
)

BASE_PATHS=("${DEFAULT_BASE_PATHS[@]}")
DRY_RUN=0
ALL_SITES=0
BACKUP_PERMS=1
VERBOSE=0
INPUT=""
BACKUP_DIR="/tmp/wp-perms-backup"

# -------------------------
# Logging
# -------------------------

log() {
  local level="$1"
  local message="$2"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local log_entry="$timestamp [$level] $message"
  
  echo "$log_entry" | tee -a "$LOG_FILE"
}

log_info() {
  log "INFO" "$1"
}

log_warn() {
  log "WARN" "$1"
}

log_error() {
  log "ERROR" "$1"
}

# -------------------------
# Spinner with error handling
# -------------------------

SPINNER_ENABLED=0
[[ -t 1 ]] && SPINNER_ENABLED=1

execute_with_spinner() {
  local msg="$1"
  shift
  local command="$*"
  local exit_code=0
  local output=""
  
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [dry-run] $msg: $command"
    return 0
  fi
  
  if [[ "$SPINNER_ENABLED" -eq 1 ]] && [[ "$VERBOSE" -eq 0 ]]; then
    # Show spinner for long-running operations
    (
      eval "$command" >/tmp/spinner-output.$$ 2>&1
      echo $? >/tmp/spinner-exit.$$
    ) &
    
    local pid=$!
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    
    while kill -0 "$pid" 2>/dev/null; do
      for (( i=0; i<${#spinstr}; i++ )); do
        printf "\r  %s %s" "$msg" "${spinstr:i:1}"
        sleep 0.1
      done
    done
    
    wait "$pid"
    exit_code=$(cat /tmp/spinner-exit.$$)
    output=$(cat /tmp/spinner-output.$$)
    rm -f /tmp/spinner-output.$$ /tmp/spinner-exit.$$
    
    if [[ $exit_code -eq 0 ]]; then
      printf "\r  %s ✔\n" "$msg"
    else
      printf "\r  %s ❌\n" "$msg"
      [[ -n "$output" ]] && echo "    Error: $output"
    fi
  else
    # No spinner, just output
    echo "  $msg..."
    if eval "$command"; then
      echo "  $msg ✔"
    else
      echo "  $msg ❌"
      exit_code=1
    fi
  fi
  
  return $exit_code
}

# -------------------------
# Backup/Restore functions
# -------------------------

backup_permissions() {
  local site_path="$1"
  local backup_file="$BACKUP_DIR/$(basename "$site_path")-$(date +%s).tar.gz"
  
  mkdir -p "$BACKUP_DIR"
  
  # Backup ownership and permissions
  execute_with_spinner "📦 Backing up permissions" \
    "find \"$site_path\" -printf '%p %u %g %m\\n' > \"${backup_file%.*}.perms\" 2>/dev/null || true"
  
  # Backup ACLs if available
  if command -v getfacl &>/dev/null; then
    execute_with_spinner "📦 Backing up ACLs" \
      "getfacl -R \"$site_path\" > \"${backup_file%.*}.acl\" 2>/dev/null || true"
  fi
  
  echo "    Backup saved to: ${backup_file%.*}.{perms,acl}"
}

restore_permissions() {
  local site_path="$1"
  local backup_base="$2"
  
  if [[ ! -f "${backup_base}.perms" ]]; then
    log_error "No backup found for $site_path"
    return 1
  fi
  
  log_info "Restoring permissions for $site_path"
  
  # Restore from backup
  while IFS=' ' read -r file user group mode; do
    [[ -e "$file" ]] || continue
    chown "$user:$group" "$file" 2>/dev/null || true
    chmod "$mode" "$file" 2>/dev/null || true
  done < "${backup_base}.perms"
  
  # Restore ACLs if available
  if [[ -f "${backup_base}.acl" ]] && command -v setfacl &>/dev/null; then
    setfacl --restore="${backup_base}.acl" 2>/dev/null || true
  fi
  
  log_info "Permissions restored for $site_path"
}

# -------------------------
# Helper functions
# -------------------------

validate_site() {
  local site_path="$1"
  
  # Safety checks
  case "$site_path" in
    "/"|"/bin"|"/boot"|"/dev"|"/etc"|"/home"|"/lib"|"/lib64"|"/proc"|"/root"|"/run"|"/sbin"|"/sys"|"/tmp"|"/usr"|"/var")
      log_error "Refusing to process system directory: $site_path"
      return 1
      ;;
    "/var"|"/var/www"|"/var/www/html"|"/srv"|"/srv/www")
      log_error "Refusing unsafe base directory: $site_path"
      return 1
      ;;
  esac
  
  # WordPress validation
  if [[ ! -f "$site_path/wp-config.php" ]]; then
    log_error "Not a WordPress site (missing wp-config.php): $site_path"
    return 1
  fi
  
  if [[ ! -d "$site_path/wp-content" ]]; then
    log_error "Invalid WordPress installation: $site_path"
    return 1
  fi
  
  return 0
}

get_current_ownership() {
  local site_path="$1"
  stat -c "%U:%G %n" "$site_path" 2>/dev/null || echo "Unknown"
}

discover_sites() {
  local sites=()
  
  for base in "${BASE_PATHS[@]}"; do
    [[ -d "$base" ]] || continue
    log_info "Scanning for WordPress sites in: $base"
    
    # Use find with null delimiter for safety
    while IFS= read -r -d '' config_file; do
      local site_dir="$(dirname "$config_file")"
      
      # Don't add duplicates
      if ! printf '%s\n' "${sites[@]}" | grep -q "^$site_dir$"; then
        sites+=("$site_dir")
      fi
    done < <(find "$base" -mindepth 1 -maxdepth 3 -type f -name "wp-config.php" -print0 2>/dev/null)
  done
  
  printf "%s\n" "${sites[@]}"
}

# -------------------------
# Permission functions
# -------------------------

secure_wp_config() {
  local site_path="$1"
  
  execute_with_spinner "🔒 Securing wp-config.php" \
    "chgrp \"$WS_GROUP\" \"$site_path/wp-config.php\" && chmod $WP_CONFIG_PERMS \"$site_path/wp-config.php\""
}

secure_wp_content() {
  local site_path="$1"
  
  # Set group ownership and permissions
  execute_with_spinner "🧩 Setting wp-content permissions" \
    "chgrp -R \"$WS_GROUP\" \"$site_path/wp-content\" && \
     find \"$site_path/wp-content\" -type d -exec chmod $WP_CONTENT_DIR_PERMS {} \\; && \
     find \"$site_path/wp-content\" -type f -exec chmod $WP_CONTENT_FILE_PERMS {} \\; && \
     find \"$site_path/wp-content\" -type d -exec chmod g+s {} \\;"
}

disable_xmlrpc() {
  local site_path="$1"
  
  if [[ -f "$site_path/xmlrpc.php" ]]; then
    execute_with_spinner "🚫 Disabling XML-RPC" \
      "chmod 000 \"$site_path/xmlrpc.php\""
  fi
}

secure_wp_includes() {
  local site_path="$1"
  
  if [[ -d "$site_path/wp-includes" ]]; then
    execute_with_spinner "🔒 Securing wp-includes" \
      "chmod 750 \"$site_path/wp-includes\""
  fi
}

secure_debug_log() {
  local site_path="$1"
  
  local debug_log="$site_path/wp-content/debug.log"
  if [[ -f "$debug_log" ]]; then
    execute_with_spinner "📝 Securing debug.log" \
      "chmod 000 \"$debug_log\""
  fi
}

disable_directory_listing() {
  local site_path="$1"
  
  # Create .htaccess in uploads directory to disable directory listing
  local uploads_htaccess="$site_path/wp-content/uploads/.htaccess"
  if [[ ! -f "$uploads_htaccess" ]]; then
    execute_with_spinner "📁 Disabling directory listings" \
      "echo 'Options -Indexes' > \"$uploads_htaccess\" && \
       chmod 644 \"$uploads_htaccess\" && \
       chgrp \"$WS_GROUP\" \"$uploads_htaccess\""
  fi
}

remove_example_files() {
  local site_path="$1"
  
  execute_with_spinner "🗑️ Removing example config files" \
    "rm -f \"$site_path/wp-config-sample.php\" \"$site_path/readme.html\" \"$site_path/license.txt\" 2>/dev/null || true"
}

set_base_permissions() {
  local site_path="$1"
  
  # Only change ownership of WordPress files, not everything recursively
  execute_with_spinner "👤 Setting ownership" \
    "chown -R \"$WP_OWNER:$WP_GROUP\" \"$site_path\""
  
  # Set safe default permissions
  execute_with_spinner "🔐 Setting base permissions" \
    "find \"$site_path\" -type d -exec chmod 755 {} \\; && \
     find \"$site_path\" -type f -exec chmod 644 {} \\;"
}

# -------------------------
# Site processing
# -------------------------

process_site() {
  local site_path="$1"
  local backup_base=""
  
  log_info "Processing site: $site_path"
  
  # Show current state
  echo "    Current ownership: $(get_current_ownership "$site_path")"
  
  # Validate site
  if ! validate_site "$site_path"; then
    return 1
  fi
  
  # Multisite detection
  if grep -q "MULTISITE.*true" "$site_path/wp-config.php" 2>/dev/null; then
    log_info "Multisite detected"
  fi
  
  # Create backup
  if [[ "$BACKUP_PERMS" -eq 1 ]]; then
    backup_permissions "$site_path"
    backup_base="$BACKUP_DIR/$(basename "$site_path")-latest"
  fi
  
  # Apply changes
  echo "  Applying security hardening..."
  
  set_base_permissions "$site_path"
  secure_wp_config "$site_path"
  secure_wp_content "$site_path"
  disable_xmlrpc "$site_path"
  secure_wp_includes "$site_path"
  secure_debug_log "$site_path"
  disable_directory_listing "$site_path"
  remove_example_files "$site_path"
  
  # Secure .htaccess if present
  if [[ -f "$site_path/.htaccess" ]]; then
    execute_with_spinner "📄 Securing .htaccess" \
      "chmod 644 \"$site_path/.htaccess\" && chgrp \"$WS_GROUP\" \"$site_path/.htaccess\""
  fi
  
  # Verify changes
  echo "    New ownership: $(get_current_ownership "$site_path")"
  
  # Check for common issues
  if [[ "$(stat -c "%a" "$site_path/wp-config.php" 2>/dev/null)" != "$WP_CONFIG_PERMS" ]]; then
    log_warn "wp-config.php permissions may not be set correctly"
  fi
  
  log_info "Completed: $site_path"
  echo
}

# -------------------------
# Usage
# -------------------------

usage() {
  cat <<EOF
WordPress Permissions & Hardening Tool
Version: 2.0

Usage:
  $0 [OPTIONS] [SITE_PATH|DOMAIN]

Options:
  --dry-run            Show what would be done without making changes
  --all-sites          Run on all WordPress sites found in base paths
  --base-path=PATH     Add custom base path for site discovery (repeatable)
  --no-backup          Skip permission backup (not recommended)
  --verbose            Show detailed output
  --owner=USER         Set file owner (default: www-data)
  --group=GROUP        Set file group (default: www-data)
  --ws-group=GROUP     Set web server group (default: www-data)
  --restore=PATH       Restore permissions from backup
  --help               Show this help message

Examples:
  $0 example.com
  $0 --dry-run /var/www/example.com
  $0 --all-sites --verbose
  $0 --owner=webadmin --group=webgroup example.com
  $0 --restore=/tmp/wp-perms-backup/example-latest

Base paths searched: ${DEFAULT_BASE_PATHS[*]}
Log file: $LOG_FILE
Backup directory: $BACKUP_DIR
EOF
  exit 0
}

# -------------------------
# Parse arguments
# -------------------------

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --all-sites)
      ALL_SITES=1
      shift
      ;;
    --no-backup)
      BACKUP_PERMS=0
      shift
      ;;
    --verbose)
      VERBOSE=1
      SPINNER_ENABLED=0  # Disable spinner in verbose mode
      shift
      ;;
    --base-path=*)
      BASE_PATHS+=("${1#*=}")
      shift
      ;;
    --owner=*)
      WP_OWNER="${1#*=}"
      shift
      ;;
    --group=*)
      WP_GROUP="${1#*=}"
      shift
      ;;
    --ws-group=*)
      WS_GROUP="${1#*=}"
      shift
      ;;
    --restore=*)
      RESTORE_BACKUP="${1#*=}"
      shift
      ;;
    --help|-h)
      usage
      ;;
    -*)
      log_error "Unknown option: $1"
      usage
      ;;
    *)
      INPUT="$1"
      shift
      ;;
  esac
done

# -------------------------
# Main execution
# -------------------------

# Check for root privileges if not dry-run
if [[ "$DRY_RUN" -eq 0 ]] && [[ "$EUID" -ne 0 ]]; then
  log_error "This script must be run as root for permission changes"
  exit 1
fi

# Initialize log
mkdir -p "$(dirname "$LOG_FILE")"
log_info "Starting WordPress permissions tool"
log_info "Options: DRY_RUN=$DRY_RUN, ALL_SITES=$ALL_SITES, BACKUP=$BACKUP_PERMS"

# Handle restore request
if [[ -n "${RESTORE_BACKUP:-}" ]]; then
  site_name=$(basename "$RESTORE_BACKUP" | sed 's/-latest$//')
  for base in "${BASE_PATHS[@]}"; do
    if [[ -d "$base/$site_name" ]]; then
      restore_permissions "$base/$site_name" "$RESTORE_BACKUP"
      exit 0
    fi
  done
  log_error "Could not find site to restore for backup: $RESTORE_BACKUP"
  exit 1
fi

# Validate input
if [[ "$ALL_SITES" -eq 0 ]] && [[ -z "$INPUT" ]]; then
  log_error "Either specify a site or use --all-sites"
  usage
fi

# Discover targets
TARGETS=()

if [[ "$ALL_SITES" -eq 1 ]]; then
  log_info "Discovering all WordPress sites..."
  mapfile -t TARGETS < <(discover_sites)
  
  if [[ "${#TARGETS[@]}" -eq 0 ]]; then
    log_error "No WordPress sites found in base paths"
    exit 1
  fi
  
  log_info "Found ${#TARGETS[@]} site(s)"
else
  if [[ "$INPUT" == /* ]]; then
    TARGETS+=("$INPUT")
  else
    for base in "${BASE_PATHS[@]}"; do
      if [[ -d "$base/$INPUT" ]]; then
        TARGETS+=("$base/$INPUT")
        break
      fi
    done
  fi
fi

[[ "${#TARGETS[@]}" -eq 0 ]] && {
  log_error "No valid targets found"
  exit 1
}

# Process each site
SUCCESS_COUNT=0
FAIL_COUNT=0

for SITE_PATH in "${TARGETS[@]}"; do
  SITE_PATH=$(realpath -s "$SITE_PATH" 2>/dev/null || echo "$SITE_PATH")
  
  echo
  echo "================================================================="
  
  if process_site "$SITE_PATH"; then
    ((SUCCESS_COUNT++))
  else
    ((FAIL_COUNT++))
  fi
done

# Summary
echo
echo "================================================================="
log_info "Processing complete"
echo "  Successful: $SUCCESS_COUNT"
echo "  Failed:     $FAIL_COUNT"
echo "  Log file:   $LOG_FILE"

if [[ "$BACKUP_PERMS" -eq 1 ]] && [[ "$DRY_RUN" -eq 0 ]]; then
  echo "  Backups:    $BACKUP_DIR"
  echo "  To restore: $0 --restore=$BACKUP_DIR/site-name-latest"
fi

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi

log_info "All tasks completed successfully"
exit 0
