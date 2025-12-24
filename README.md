# WordPress Hardening Tool 🛡️

A safe, production-ready Bash script for hardening WordPress file permissions and reducing common attack surfaces.

Designed for sysadmins, developers, and VPS users who want a **repeatable, auditable, low-risk** way to secure WordPress installs.

---

## ✨ Features

- 🔐 Secure WordPress file & directory permissions (per WordPress guidelines)
- 🧹 Removes insecure example config files
- 🚫 Disables XML-RPC (common brute-force & DDoS vector)
- 📄 Secures `.htaccess`
- 🌀 Terminal spinner (automatically disabled in cron / non-TTY)
- 🧪 `--dry-run` mode (no changes made)
- 🌍 Accepts **full path OR domain name**
- 🔍 Auto-discovers WordPress installs
- 🏢 `--all-sites` mode
- 🗂️ Automatic permission backups (with optional restore)
- 🧠 Multisite detection (informational only)
- 🛑 Strong safety checks to prevent destructive usage
- 📜 Detailed logging to `/var/log/wordpress-permissions.log`

## ✨ New in Version 2.0

- ✅ Backup & Restore - Automatic permission backups before changes
- ✅ Enhanced Security - Additional hardening steps (wp-includes, debug.log, directory listings)
- ✅ Better Error Handling - Commands fail safely with proper feedback
- ✅ Detailed Logging - Timestamped logs with error levels
- ✅ Validation - Pre-flight checks and post-change verification
- ✅ Restore Feature - Rollback changes if something goes wrong
- ✅ Configurable Permissions - Adjust for your specific needs

---

## 📦 Requirements

- Linux (tested on Ubuntu / Debian)
- Bash 4+
- Root or sudo privileges
- WordPress installed under common web roots

---

## 🚀 Installation

```bash
git clone https://github.com/haywardgg/wp-hardening-tool.git
cd wp-hardening-tool
chmod +x wp-hardening.sh
```

---

## 🧪 Usage

### Harden a single site (domain name)
```bash
sudo ./wp-hardening.sh example.com
```

### Harden a site by full path
```bash
sudo ./wp-hardening.sh /var/www/html/example.com
```

### Dry run (no changes made)
```bash
sudo ./wp-hardening.sh --dry-run example.com
```

### Harden all WordPress sites on the server
```bash
sudo ./wp-hardening.sh --all-sites
```

### Use a custom base path
```bash
sudo ./wp-hardening.sh --base-path=/srv/www example.com
```

Multiple `--base-path` flags may be supplied.

### Skip backups
```bash
sudo ./wp-hardening.sh --no-backup example.com
```

### Restore permissions from the latest backup
```bash
sudo ./wp-hardening.sh --restore=/tmp/wp-perms-backup/example-latest
```

### Increase verbosity (disables spinner)
```bash
sudo ./wp-hardening.sh --verbose example.com
```

### Advanced examples

#### Custom base path for site discovery
```bash
sudo ./wp-hardening.sh --base-path=/srv/www example.com
```

#### Custom ownership (for non-www-data setups)
```bash
sudo ./wp-hardening.sh --owner=webadmin --group=webgroup example.com
```

#### Skip backup (not recommended for production)
```bash
sudo ./wp-hardening.sh --no-backup example.com
```

#### Restore from previous backup
```bash
sudo ./wp-hardening.sh --restore=/tmp/wp-perms-backup/example-latest
```

#### Dry run with custom web server group
```bash
sudo ./wp-hardening.sh --dry-run --ws-group=nginx example.com
```

---

## 🔍 How Target Resolution Works

When a **domain name** is supplied (e.g. `example.com`), the script searches for:

- `/var/www/example.com`
- `/var/www/html/example.com`
- Any additional `--base-path` values

When a **full path** is supplied, it is used directly after validation.

---

## 🔒 What This Script Does

### Core Security Hardening

- Sets safe file permissions (directories `755`, files `644`)
- Secures `wp-config.php` (permissions `600`, webserver group)
- Allows WordPress to write to `wp-content` (directories `775`, files `664`)
- Sets setgid on `wp-content` directories for proper group inheritance

### Additional Hardening

- Disables `xmlrpc.php` (sets `000` permissions)
- Secures `wp-includes` directory (sets `750` permissions)
- Protects `wp-content/debug.log` (sets `000` permissions when present)
- Disables directory listing in `wp-content/uploads` via `.htaccess`
- Removes example files: `wp-config-sample.php`, `readme.html`, `license.txt`
- Secures `.htaccess` (sets `644` permissions, webserver group)

### Safety Features

- Creates permission backups before changes
- Validates WordPress structure before proceeding
- Prevents execution on system directories
- Post-change verification
- Detailed logging to `/var/log/wordpress-permissions.log`

---

## 🗂️ Backups & Logging

- Permission backups are created by default in `/tmp/wp-perms-backup` (disable with `--no-backup`).
- Restore the most recent backup for a site via `--restore=/tmp/wp-perms-backup/site-name-latest`.
- Actions and warnings are logged to `/var/log/wordpress-permissions.log`.

---

## 🛡️ Safety Guarantees

This script is intentionally defensive.

It **WILL NOT**:
- Run on `/`, `/var`, `/var/www`, or `/var/www/html`
- Run on directories that are not WordPress
- Modify directories without `wp-config.php`
- Fail silently — all critical errors stop execution

It **DOES**:
- Validate WordPress structure before changes
- Refuse unsafe or ambiguous targets
- Support `--dry-run` to preview changes
- Create permission backups by default (stored in `/tmp/wp-perms-backup`)
- Provide restoration via `--restore=/tmp/wp-perms-backup/site-name-latest`
- Operate idempotently (safe to run repeatedly)

---

## ⚠️ Important Notes

- Must be run as **root or via sudo**
- XML-RPC is disabled by default  
  (re-enable manually if required by your setup)
- Always test with `--dry-run` on production servers first

---

## 🕒 Cron Usage

The script automatically disables animations when run from cron or other non-TTY environments.

### Example cron jobs

#### Daily at 3 AM
```cron
0 3 * * * root /usr/local/bin/wp-hardening.sh --all-sites --no-backup
```

#### Weekly with backups (Sunday at 2 AM)
```cron
0 2 * * 0 root /usr/local/bin/wp-hardening.sh --all-sites
```

#### With custom log location
```cron
0 4 * * * root /usr/local/bin/wp-hardening.sh --all-sites >> /var/log/wp-hardening-cron.log 2>&1
```

Cron output will be clean and readable.

---

## 🐛 Troubleshooting

### Common Issues

**"Permission denied" errors:**

- Ensure script is run as root/sudo
- Check SELinux/AppArmor permissions

**"No WordPress sites found":**

- Use `--base-path` to add custom locations
- Verify `wp-config.php` exists in target directories

**"Refusing unsafe directory":**

- Script prevents execution on system directories
- Use full path to specific WordPress install

**Backup failures:**

- Check `/tmp` directory permissions
- Ensure `getfacl` is installed for ACL backups

---

## 🧠 Multisite Detection

If WordPress multisite is detected, the script will:
- Notify the user
- Apply the same permission logic

No multisite-specific changes are made.

---

## ❓ What This Script Is NOT

- A malware scanner
- A firewall
- A replacement for server-level security
- A WordPress plugin

It is a **baseline hardening tool**, not a full security suite.

---

## 📜 License

MIT License - see [LICENSE](LICENSE) file for details.

---

## 🤝 Contributing

Contributions welcome! Please:

- Fork the repository
- Create a feature branch
- Submit a pull request

Guidelines:

- Maintain backward compatibility
- Add tests for new features
- Update documentation
- Follow existing code style

---

## 👤 Author

**Lee Hayward**

Making WordPress servers safer by default.

---

## ⭐ Support

If this tool helps you, please:

- Star the repository
- Share with other WordPress administrators
- Report issues and suggest improvements

Remember: Security is a process, not a product. Regular updates, monitoring, and defense-in-depth are essential for true security.
