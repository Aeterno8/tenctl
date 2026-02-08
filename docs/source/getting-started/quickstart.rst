Quick Start Guide
=================

Step 1: Verify Installation
----------------------------

.. code-block:: bash

   tenctl --version
   tenctl-list

Expected output:

.. code-block:: bash

   root@pve:~# tenctl --version
   Tenctl - Multi-Tenant Management for Proxmox VE
   Version: 2.0.0
   Mode: installed
   Architecture: Git-style (standalone subcommands)

   Dependencies:
   pvesh:  ✓ installed
   jq:     ✓ installed
   flock:  ✓ installed

   Subcommands:
   14 standalone commands available

   root@pve:~# tenctl-list
   root@pve:~# 

Step 2: Create Your First Tenant
---------------------------------

Create a tenant named "companyA":

.. code-block:: bash

   tenctl-add \
     -n "companyA" \
     -c 8 \
     -r 16384 \
     -s 500 \
     -e "admin@companya.com"

**Command Breakdown:**

- ``-n "companyA"`` - Tenant name
- ``-c 8`` - 8 CPU cores
- ``-r 16384`` - 16 GB RAM (in MB)
- ``-s 500`` - 500 GB storage
- ``-e`` - Contact email

**What Happens:**

The system automatically:

1. Creates resource pool: ``tenant_companyA``
2. Allocates VLAN from the configured range (first available)
3. Assigns subnet from ``BASE_SUBNET`` (first available /24)
4. Creates user group: ``group_companyA``
5. Creates admin user: ``admin_companyA@pve`` and sets ACLs
6. Stores configuration in pmxcfs (``/etc/pve/tenants``)

Step 3: Verify Tenant
----------------------

List tenants:

.. code-block:: bash

   tenctl-list

Output:

.. code-block:: text

   Proxmox Multi-Tenant Overview
   ==============================

   Tenant               Pool ID            Subnet              VLAN     CPU Limit   RAM(MB)  Storage(GB)  VM Count
   companyA            tenant_companyA    10.100.0.0/24       100      8           16384    500          0

Check resource usage:

.. code-block:: bash

   tenctl-usage -n companyA

Step 4: Verify in Proxmox UI
-----------------------------

Open Proxmox web interface:

1. **Datacenter** → **Permissions** → **Pools** - See ``tenant_companyA``
2. **Datacenter** → **Permissions** → **Groups** - See ``group_companyA``
3. **Datacenter** → **Permissions** - See ACLs for ``admin_companyA@pve``

Common Operations
=================

Modify Tenant Resources
-----------------------

Increase CPU and RAM:

.. code-block:: bash

   tenctl-modify -n companyA -c 16 -r 32768

Suspend Tenant
--------------

Temporarily disable access:

.. code-block:: bash

   tenctl-suspend -n companyA

This disables the tenant user account. Use ``--stop-vms`` to stop running VMs.

Resume Tenant
-------------

Reactivate:

.. code-block:: bash

   tenctl-resume -n companyA

Monitor Health
--------------

Check tenant components:

.. code-block:: bash

   tenctl-health -n companyA

Backup Configuration
--------------------

Export tenant config:

.. code-block:: bash

   tenctl-backup -n companyA

View Audit Log
--------------

See operation history:

.. code-block:: bash

   tenctl-audit -n companyA

Remove Tenant
-------------

**WARNING:** Permanently removes tenant.

.. code-block:: bash

   tenctl-remove -n companyA

Confirm by typing tenant name:

Best Practices
==============

**Naming Conventions**
  Use lowercase with hyphens: ``company-name``, ``project-name``

**Resource Planning**
  Start conservative. Easy to increase with ``tenctl-modify``.

**Regular Monitoring**
  Use ``tenctl-usage`` and ``tenctl-health`` regularly.

**Backup Configuration**
  Periodically backup: ``tenctl-backup -n <name>``

**Audit Trail**
  Review logs: ``tenctl-audit``
