System Architecture
===================

Tenant Isolation Model
-----------------------

Multiple layers ensure complete isolation:

**Layer 1: Resource Pools**
  Proxmox resource pools providing isolation and grouping of tenants

**Layer 2: Network VLANs**
  Dedicated VLAN per tenant for network isolation

**Layer 3: User Groups**
  Tenant-specific groups with restricted permissions

**Layer 4: ACLs**
  Fine-grained access control per tenant

Command Structure
-----------------

Git-style subcommands::

   tenctl              # Main entry point
   tenctl-init         # System initialization
   tenctl-add          # Create tenant
   tenctl-modify       # Update tenant
   tenctl-suspend      # Suspend tenant
   tenctl-resume       # Resume tenant
   tenctl-remove       # Remove tenant
   tenctl-list         # List tenants
   tenctl-health       # Health checks
   tenctl-usage        # Resource usage
   tenctl-audit        # Audit trail
   tenctl-backup       # Backup config
   tenctl-restore      # Restore config
   tenctl-vyos         # VyOS integration

Library Modules
---------------

18 modules organized by function:

- **Core** (``lib/core/``) - Configuration, logging, validation
- **Proxmox** (``lib/proxmox/``) - API, pools, users, network
- **Tenant** (``lib/tenant/``) - Lifecycle operations
- **Cluster** (``lib/cluster/``) - Multi-node sync
- **Utils** (``lib/utils/``) - Helpers
- **VyOS** (``lib/vyos/``) - Router integration

Troubleshooting
===============

Installation Issues
-------------------

**Problem: pvesh not found**

.. code-block:: text

   ERROR: Missing required dependencies: pvesh

**Solution:** Install on Proxmox VE node. ``pvesh`` is part of PVE.

**Problem: Permission denied**

.. code-block:: text

   ERROR: This script must be run as root

**Solution:** Run with ``sudo`` or as root.

**Problem: Cluster nodes unreachable**

.. code-block:: text

   WARNING: Cannot reach node2

**Solution:**

- Check network connectivity
- Verify SSH access: ``ssh node2``
- Use ``--local-only`` to skip cluster sync

Tenant Creation Issues
----------------------

**Problem: VLAN allocation failed**

.. code-block:: text

   ERROR: No available VLAN IDs in range <VLAN_START>-<VLAN_END>

**Solution:** Increase VLAN pool in ``/usr/local/share/tenctl/config/tenant.conf``.

**Problem: Pool already exists**

.. code-block:: text

   ERROR: Failed to create resource pool

**Solution:** Choose different tenant name or remove existing pool.
