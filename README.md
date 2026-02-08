# Tenctl

Multi-tenant management CLI for Proxmox VE.

---

## ⚠️ **CRITICAL WARNING - ACTIVE DEVELOPMENT** ⚠️

> **🚨 THIS PROJECT IS UNDER HEAVY DEVELOPMENT AND NOT READY FOR PRODUCTION USE 🚨**
>
> **READ THIS CAREFULLY BEFORE PROCEEDING:**
>
> - ❌ **NOT PRODUCTION READY** - This software is in active development and may contain serious bugs
> - 💥 **BREAKING CHANGES EXPECTED** - APIs, commands, and configurations may change without notice between releases
> - 🐛 **KNOWN AND UNKNOWN BUGS** - Expect errors, crashes, and unexpected behavior
> - 🔥 **DATA LOSS POSSIBLE** - This tool manipulates critical infrastructure. Data loss or service disruption may occur
> - ⚡ **NO STABILITY GUARANTEES** - No backwards compatibility or upgrade paths guaranteed
> - 🛑 **USE AT YOUR OWN RISK** - You are solely responsible for any consequences of using this software
>
> **By proceeding, you acknowledge:**
> - You understand this is experimental software
> - You accept full responsibility for any damage, data loss, or service interruption
> - You will NOT use this in production environments without thorough testing
> - You will maintain backups and have rollback procedures in place
>
> **Recommended for:** Development, testing, and experimentation only.
>
> **NOT recommended for:** Production systems, critical infrastructure, or environments where stability is required.

---

**Version:** 2.0.0 (Alpha - Unstable)

## Features

- Complete tenant isolation (resource pools, VLANs, user groups, ACLs)
- Network integration with automatic VLAN allocation
- Resource monitoring via systemd service
- Cluster-aware multi-node synchronization
- Pure Bash implementation

## Quick Start

### Installation

```bash
curl -sSL https://raw.githubusercontent.com/Aeterno8/tenctl/master/bootstrap.sh | bash
```

### Initialize

```bash
tenctl-init
```

### Create Tenant

```bash
tenctl-add -n "company" -c 8 -r 16384 -s 500 -e "admin@company.com"
```

## Documentation

Build locally:

```bash
cd docs
pip install -r requirements.txt
make html
# Open docs/build/html/index.html
```

## CLI Commands

- `tenctl` - Main entry point
- `tenctl-init` - Initialize system
- `tenctl-add` - Create tenant
- `tenctl-modify` - Modify tenant
- `tenctl-remove` - Remove tenant
- `tenctl-list` - List tenants
- `tenctl-health` - Health check
- `tenctl-usage` - Resource usage
- `tenctl-backup/restore` - Backup management
- `tenctl-suspend/resume` - Suspend/resume tenant
- `tenctl-audit` - Audit log
- `tenctl-vyos` - VyOS integration

Run `tenctl --help` for complete reference.

## Requirements

- Proxmox VE 9.0+
- Debian 11+
- Bash 4.0+
- Root access

## License

MIT License
