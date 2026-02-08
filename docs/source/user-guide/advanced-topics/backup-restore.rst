Backup and Restore
==================

Backup Operations
-----------------

Export tenant configuration:

.. code-block:: bash

   tenctl-backup -n tenant_name

This exports:

- Tenant metadata
- Resource limits
- VLAN and subnet configuration
- User and group information
- VM/container inventory metadata

Restore Operations
------------------

Restore tenant from backup:

.. code-block:: bash

   tenctl-restore --file /var/backups/tenctl/tenant_name_YYYYMMDD_HHMMSS.tar.gz

**Important:** VM disk images are not included; back up and restore them using Proxmox Backup Server or ``vzdump``.

Best Practices
--------------

**Regular Backups**
  Backup configs before major changes.

**Version Control**
  Avoid storing backups in Git (archives can include credentials and metadata).

**Test Restores**
  Periodically test restore process.
