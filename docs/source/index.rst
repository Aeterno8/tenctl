.. Tenctl - Multi-Tenant Management for Proxmox VE documentation master file

Tenctl - Multi-Tenant Management for Proxmox VE
===============================================

**Version:** 1.0.2

A pure Bash CLI tool for managing multi-tenant environments on Proxmox VE clusters. This system provides complete tenant isolation through resource pools, VLANs, user groups, and VyOS integration.

.. grid:: 2
    :gutter: 3

    .. grid-item-card:: 🚀 Getting Started
        :link: getting-started/index
        :link-type: doc

        Installation, quickstart guide, and basic concepts for new users.

    .. grid-item-card:: 📘 User Guide
        :link: user-guide/index
        :link-type: doc

        Complete guide to tenant lifecycle, networking, and resource management.

    .. grid-item-card:: 🔧 Admin Guide
        :link: admin-guide/index
        :link-type: doc

        Cluster setup, configuration reference, security, and troubleshooting.

    .. grid-item-card:: 📚 Reference
        :link: reference/index
        :link-type: doc

        CLI command reference and error codes.

Key Features
------------

- **Complete Tenant Isolation**: Resource pools, VLANs, user groups, and permissions
- **Network Integration**: Automatic VLAN allocation with VyOS router support
- **Resource Management**: CPU, RAM, and storage monitoring via systemd service
- **Cluster-Aware**: Multi-node synchronization via pmxcfs
- **Modular Design**: Git-style architecture with 18 library modules
- **Pure Bash**: No external dependencies beyond Proxmox VE APIs
- **Audit Trail**: Complete tenant lifecycle logging

Quick Start
-----------

Install using the bootstrap script:

.. code-block:: bash

   curl -sSL https://raw.githubusercontent.com/Aeterno8/tenctl/master/bootstrap.sh | bash

Create your first tenant:

.. code-block:: bash

   tenctl add -n "companyA" -c 8 -r 16384 -s 500 -e "admin@companya.com"

See the :doc:`getting-started/index` guide for detailed walkthrough.

CLI Commands
------------

The system provides 14 commands for tenant management:

.. list-table::
   :header-rows: 1
   :widths: 25 75

   * - Command
     - Description
   * - ``tenctl``
     - Main entry point and help system
   * - ``tenctl-init``
     - Initialize the system configuration
   * - ``tenctl-add``
     - Create a new tenant
   * - ``tenctl-modify``
     - Modify tenant configuration
   * - ``tenctl-suspend``
     - Suspend a tenant (pause VMs, revoke permissions)
   * - ``tenctl-resume``
     - Resume a suspended tenant
   * - ``tenctl-remove``
     - Remove a tenant completely
   * - ``tenctl-list``
     - List all tenants
   * - ``tenctl-health``
     - Check tenant health status
   * - ``tenctl-usage``
     - Display resource usage statistics
   * - ``tenctl-audit``
     - Show audit log for tenants
   * - ``tenctl-backup``
     - Backup tenant configuration
   * - ``tenctl-restore``
     - Restore tenant from backup
   * - ``tenctl-vyos``
     - Configure VyOS router integration

System Requirements
-------------------

- Proxmox VE 9.0 or later
- Bash 4.0+
- Root access on Proxmox nodes
- VyOS router (optional, for network isolation)

Table of Contents
-----------------

.. toctree::
   :maxdepth: 2
   :caption: Documentation

   getting-started/index
   user-guide/index
   admin-guide/index
   reference/index
   appendix/index

Indices and Tables
==================

* :ref:`genindex`
* :ref:`search`

License
=======

This project is licensed under the MIT License. See :doc:`appendix/license` for full license text.

Author
======

**Aleksa Savić**

- Project Repository: https://github.com/Aeterno8/tenctl
- Documentation: Built with Sphinx and ReadTheDocs
