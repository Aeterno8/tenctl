Operations
==========

Cluster setup, security, troubleshooting, performance, and maintenance.

Cluster Setup
-------------

Prerequisites
-------------

- All nodes in Proxmox cluster
- SSH access between nodes
- Shared storage (optional but recommended)

Installation
------------

Automatic cluster-wide installation:

.. code-block:: bash

   curl -sSL https://raw.githubusercontent.com/Aeterno8/tenctl/master/bootstrap.sh | bash

The installer detects cluster nodes and can install on all online nodes (prompted unless ``-y`` is used).

Manual installation per node:

.. code-block:: bash

   # On each node:
   curl -sSL https://raw.githubusercontent.com/Aeterno8/tenctl/master/bootstrap.sh | bash -s -- --local-only

Configuration Synchronization
------------------------------

Configuration is automatically synchronized via pmxcfs. All tenant configurations in ``/etc/pve/tenants/`` replicate to all nodes.

Verify synchronization:

.. code-block:: bash

   # On each node:
   tenctl-list

All nodes should show identical tenant lists.

Security
--------

Principle of Least Privilege
-----------------------------

Tenant users receive minimal permissions:

- Access only to their resource pool
- Cannot modify network configuration
- Cannot create users
- Cannot access other tenants

Best Practices
--------------

**Regular Audits**

.. code-block:: bash

   tenctl-audit

**Credential Rotation**
  Rotate VyOS and API credentials periodically.

**Access Control**
  Use Proxmox's built-in 2FA for tenant users.

**Network Isolation**
  Ensure VLANs are properly configured on switches.

Troubleshooting
---------------

Installation Issues
-------------------

**pvesh not found**
  Ensure you're on a Proxmox VE node.

**Permission denied**
  Run as root or with sudo.

Tenant Creation
---------------

**No available VLANs**
  Increase VLAN pool range in ``/usr/local/share/tenctl/config/tenant.conf``.

**Failed to create resource pool**
  Use a different tenant name or remove the existing pool.

Network Issues
--------------

**VMs cannot communicate**
  Verify VLAN configuration on physical switches.

**No internet access**
  Check VyOS NAT rules and routing.

Cluster Issues
--------------

**Configuration not syncing**
  Verify pmxcfs is running on all nodes.

**Nodes unreachable**
  Check network connectivity and SSH access.

Performance
-----------

Optimization Tips
-----------------

**VLAN Allocation**
  Use smaller VLAN pools to reduce search time.

**Resource Pools**
  On Proxmox VE 9.0+, quotas are enforced efficiently.

**Monitoring**
  Use ``tenctl-usage`` to identify resource-intensive tenants.

Best Practices
--------------

- Limit VLAN pool size
- Regular cleanup of unused tenants
- Monitor cluster load

Maintenance
-----------

System Updates
--------------

Update Tenctl:

.. code-block:: bash

   tenctl update-cli

Configuration Backups
---------------------

Backup all tenant configurations:

.. code-block:: bash

   for tenant in $(tenctl-list --json | jq -r '.[].tenant_name'); do
       tenctl-backup -n "$tenant" --output /var/backups/tenctl
   done

Log Management
--------------

Audit logs are written to ``/var/log/tenctl/tenant-management.log`` and rotated via ``/etc/logrotate.d/tenctl``.

Best Practices
--------------

- Weekly configuration backups
- Monthly system updates
- Quarterly audit reviews
