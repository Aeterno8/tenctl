CLI Command Reference
=====================

Quick reference for all CLI commands. For detailed usage, run: ``tenctl <command> --help``

Main Command
------------

tenctl
~~~~~~

Main entry point showing available commands and version information.

.. code-block:: bash

   tenctl --help
   tenctl --version

System Management
-----------------

tenctl-init
~~~~~~~~~~~

Initialize SDN and cluster networking using values from the config file.

.. code-block:: bash

   tenctl-init

Configures SDN zones, networking, and cluster resources.

Tenant Lifecycle
----------------

tenctl-add
~~~~~~~~~~

Create new tenant with specified resources.

.. code-block:: bash

   tenctl-add -n "tenant_name" -c 8 -r 16384 -s 500 -e "email@example.com"

tenctl-modify
~~~~~~~~~~~~~

Update tenant resource limits.

.. code-block:: bash

   tenctl-modify -n tenant_name -c 16 -r 32768 -s 1000

tenctl-suspend
~~~~~~~~~~~~~~

Temporarily disable tenant (disable user account; optionally stop VMs).

.. code-block:: bash

   tenctl-suspend -n tenant_name

tenctl-resume
~~~~~~~~~~~~~

Reactivate suspended tenant.

.. code-block:: bash

   tenctl-resume -n tenant_name

tenctl-remove
~~~~~~~~~~~~~

Permanently remove tenant with confirmation prompt.

.. code-block:: bash

   tenctl-remove -n tenant_name

Information Commands
--------------------

tenctl-list
~~~~~~~~~~~

List all tenants with resource allocation and status.

.. code-block:: bash

   tenctl-list
   tenctl-list --detailed
   tenctl-list -n tenant_name

tenctl-health
~~~~~~~~~~~~~

Check tenant configuration integrity.

.. code-block:: bash

   tenctl-health -n tenant_name

Verifies: dependencies, cluster, SDN config, VLAN/subnet allocation, tenant configs, ACLs.

tenctl-usage
~~~~~~~~~~~~

View tenant resource usage statistics.

.. code-block:: bash

   tenctl-usage -n tenant_name

Shows CPU, RAM, storage usage and VM list.

tenctl-audit
~~~~~~~~~~~~

View tenant operation audit trail.

.. code-block:: bash

   tenctl-audit -n tenant_name
   tenctl-audit  # System-wide

Configuration Management
------------------------

tenctl-backup
~~~~~~~~~~~~~

Create a tenant configuration backup archive.

.. code-block:: bash

   tenctl-backup -n tenant_name

tenctl-restore
~~~~~~~~~~~~~~

Restore tenant from backup archive.

.. code-block:: bash

   tenctl-restore --file /var/backups/tenctl/tenant_name_YYYYMMDD_HHMMSS.tar.gz

Networking
----------

tenctl-vyos
~~~~~~~~~~~

VyOS router setup and integration.

.. code-block:: bash

   tenctl-vyos install
   tenctl-vyos configure --wan-ip 192.168.1.100 --wan-gw 192.168.1.1
   tenctl-vyos enable --wan-ip 192.168.1.100 --wan-gw 192.168.1.1
   tenctl-vyos test
