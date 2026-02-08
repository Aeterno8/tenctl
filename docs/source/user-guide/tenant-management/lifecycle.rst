Tenant Lifecycle
================

Creating Tenants
----------------

Use ``tenctl-add`` to create new tenants:

.. code-block:: bash

   tenctl-add -n "tenant_name" -c 8 -r 16384 -s 500 -e "admin@example.com"

Required Parameters
~~~~~~~~~~~~~~~~~~~

- ``-n, --name`` - Tenant name (must start with a letter, alphanumeric/underscore only)

Optional Parameters
~~~~~~~~~~~~~~~~~~~

- ``-c, --cpu`` - CPU cores (default from config)
- ``-r, --ram`` - RAM in MB (default from config)
- ``-s, --storage`` - Storage in GB (default from config)
- ``-e, --email`` - Admin email
- ``-v, --vlan`` - Specific VLAN ID (auto-allocated if not specified)
- ``-i, --subnet`` - Specific subnet (auto-allocated if not specified)
- ``-u, --username`` - Admin username (default: ``admin_<name>``)
- ``-p, --password`` - Admin password (default: auto-generated)

What Gets Created
~~~~~~~~~~~~~~~~~

The system automatically creates:

1. Resource pool: ``tenant_<name>``
2. VLAN allocation (first available from configured range)
3. Subnet assignment (first available /24 from ``BASE_SUBNET``)
4. User group: ``group_<name>``
5. Admin user: ``admin_<name>@pve`` (by default) and ACLs
6. Configuration in pmxcfs (``/etc/pve/tenants``)

Modifying Tenants
-----------------

Update tenant resources:

.. code-block:: bash

   tenctl-modify -n tenant_name -c 16 -r 32768 -s 1000

You can modify:

- CPU cores (``-c``)
- RAM in MB (``-r``)
- Storage in GB (``-s``)

**Note:** Resource modifications apply to pool limits. Running VMs are not automatically adjusted.

Suspending Tenants
------------------

Temporarily disable a tenant:

.. code-block:: bash

   tenctl-suspend -n tenant_name

This will:

- Disable the tenant user account
- Optionally stop VMs/containers (use ``--stop-vms``)
- Mark tenant as suspended in configuration

**Use cases:**

- Non-payment
- Security incident
- Maintenance window
- Contract suspension

Resuming Tenants
----------------

Reactivate a suspended tenant:

.. code-block:: bash

   tenctl-resume -n tenant_name

This will:

- Re-enable the tenant user account
- Optionally start VMs/containers (use ``--start-vms``)
- Mark tenant as active

Removing Tenants
----------------

Permanently remove a tenant:

.. code-block:: bash

   tenctl-remove -n tenant_name

**WARNING:** This is a destructive operation. The system will prompt for confirmation.

What Gets Removed
~~~~~~~~~~~~~~~~~

- User, user group, and ACLs
- Resource pool
- VNet/subnet and VLAN allocation (released for reuse)
- Tenant configuration
- Stored credentials file(s)

What Is Preserved
~~~~~~~~~~~~~~~~~

- External backups (if created separately)
