Getting Started
===============

Welcome to Tenctl - Multi-Tenant Management for Proxmox VE. This guide will help you install the system and create your first tenant.

What is Tenctl?
---------------

Tenctl is a Bash CLI tool that automates multi-tenant management in Proxmox VE environments. It provides complete tenant isolation through automated creation of resource pools, VLANs, user groups, and permissions.

**Key Features:**

- **Automated Tenant Creation** - Single command creates all necessary components
- **Network Isolation** - Dedicated VLANs and subnets per tenant
- **Resource Control** - CPU, RAM, and storage quotas (PVE 9.0+)
- **Cluster-Aware** - Automatic synchronization across cluster nodes
- **VyOS Integration** - Optional router integration for L3 routing

**Use Cases:**

- Service providers hosting multiple customers
- Corporate IT managing department resources
- Educational labs with isolated environments

Documentation Structure
-----------------------

.. toctree::
   :maxdepth: 2

   installation
   quickstart
   architecture

Next Steps
----------

Once you've completed the quickstart:

- :doc:`../user-guide/index` - Complete usage guide
- :doc:`../admin-guide/configuration` - Advanced configuration
- :doc:`../reference/cli-reference` - Command reference
