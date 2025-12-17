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
- 🧠 Multisite detection (informational only)
- 🛑 Strong safety checks to prevent destructive usage

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

---

## 🔍 How Target Resolution Works

When a **domain name** is supplied (e.g. `example.com`), the script searches for:

- `/var/www/example.com`
- `/var/www/html/example.com`
- Any additional `--base-path` values

When a **full path** is supplied, it is used directly after validation.

---

## 🔒 What This Script Does

- Sets safe file permissions:
  - Directories: `755`
  - Files: `644`
- Secures `wp-config.php`:
  - Group: webserver group
  - Permissions: `600`
- Allows WordPress to write to `wp-content`
- Removes:
  - `wp-config-sample.php`
  - `config-example.php`
- Disables `xmlrpc.php` by setting permissions to `000`
- Secures `.htaccess` (if present)

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

### Example cron job
```cron
0 3 * * * root /usr/local/bin/wp-hardening.sh --all-sites
```

Cron output will be clean and readable.

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

MIT License — see [LICENSE](LICENSE)

---

## 🤝 Contributing

Issues and pull requests are welcome.

Guidelines:
- Keep changes security-focused
- Avoid destructive defaults
- Maintain clear operator feedback

---

## 👤 Author

Created by **Lee Hayward**

This project exists to make WordPress servers safer by default.
Audit it. Fork it. Improve it.
