Resource Management
===================

Resource Pools
--------------

Each tenant gets a dedicated Proxmox resource pool with defined limits for CPU, RAM, and storage.

Setting Limits
~~~~~~~~~~~~~~

During creation:

.. code-block:: bash

   tenctl-add -n "tenant_name" -c 8 -r 16384 -s 500 -e "admin@example.com"

After creation:

.. code-block:: bash

   tenctl-modify -n tenant_name -c 16 -r 32768 -s 1000

Monitoring Usage
----------------

Check resource usage:

.. code-block:: bash

   tenctl-usage -n tenant_name

Output shows:

.. code-block:: text

   Tenant Resource Usage Report
   Tenant: tenant_name
   Pool: tenant_tenant_name
   Overall Status: OK
   VMs: 1 total, 1 running
   Resource Allocation:
     CPU:     2 / 8 cores (25%) [OK]
     RAM:     4096 / 16384 MB (25%) [OK]
     Storage: 50 / 500 GB (10%) [OK]

Resource Watcher
----------------

The ``tenctl-watcher`` systemd service continuously monitors tenant resource usage.

Check service status:

.. code-block:: bash

   systemctl status tenctl-watcher

View logs:

.. code-block:: bash

   journalctl -u tenctl-watcher -f
