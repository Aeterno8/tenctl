Error Codes
===========

Exit codes and error messages.

Exit Codes
----------

Exit codes vary by command. In practice:

.. list-table::
   :header-rows: 1
   :widths: 10 90

   * - Code
     - Description
   * - 0
     - Success
   * - 1
     - General error (most failures)
   * - 2
     - Health check critical error (Proxmox API unavailable)
   * - 130
     - Interrupted (SIGINT/SIGTERM)

Error Messages
--------------

Common error messages and solutions:

**ERROR: Tenant 'NAME' already exists**
   A tenant with this name already exists. Use a different name or remove the existing tenant.

**ERROR: No available VLAN IDs in range X-Y**
   VLAN pool exhausted. Increase VLAN range or remove unused tenants.

**ERROR: Failed to create resource pool**
   Proxmox API error. Check Proxmox logs and permissions.

**ERROR: This script must be run as root**
   Command must be run as root.

See :doc:`../admin-guide/operations` for more details.
