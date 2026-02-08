Installation
============

Prerequisites
-------------

Before installing, ensure you have:

**System Requirements:**
  - Proxmox VE 9.0 or later
  - Root access

**Network Requirements:**
  - VLAN support on network infrastructure
  - VyOS router (optional, for advanced networking)

Method 1: Bootstrap Install (Recommended)
------------------------------------------

One-liner installation from Git repository:

.. code-block:: bash

   curl -sSL https://raw.githubusercontent.com/Aeterno8/tenctl/master/bootstrap.sh | bash

This script will:

1. Download latest version from Git
2. Install CLI entrypoints to ``/usr/local/bin/``
3. Copy core files to ``/usr/local/share/tenctl/``
4. Install default configuration to ``/usr/local/share/tenctl/config/tenant.conf``
5. Offer cluster sync (prompted unless ``-y`` is used)

**Options:**

.. code-block:: bash

   # Non-interactive installation
   curl -sSL https://raw.githubusercontent.com/Aeterno8/tenctl/master/bootstrap.sh | bash -s -- -y

   # Local-only install (skip cluster sync)
   curl -sSL https://raw.githubusercontent.com/Aeterno8/tenctl/master/bootstrap.sh | bash -s -- --local-only

Method 2: Manual Installation
------------------------------

For more control:

**Step 1: Clone the Repository**

.. code-block:: bash

   cd /tmp
   git clone https://github.com/Aeterno8/tenctl.git
   cd tenctl

**Step 2: Run the Installer**

.. code-block:: bash

   sudo ./install.sh

**Step 3: Verify Installation**

.. code-block:: bash

   tenctl --version

Method 3: Cluster Installation
-------------------------------

To deploy across all cluster nodes:

**Step 1: Install on First Node**

.. code-block:: bash

   curl -sSL https://raw.githubusercontent.com/Aeterno8/tenctl/master/bootstrap.sh | bash

**Step 2: Automatic Cluster Sync**

The installer detects cluster membership and installs on all nodes automatically:

.. code-block:: text

   Detected cluster with 3 nodes:
     - node1 (local)
     - node2
     - node3

   Installing on all cluster nodes...

.. note::

   In interactive mode, you will be prompted before installing on other nodes.
   Use ``-y`` for non-interactive auto-approval.

**Step 3: Verify on Each Node**

.. code-block:: bash

   ssh node1 "tenctl --version"
   ssh node2 "tenctl --version"

Post-Installation Setup
========================

Initialize Configuration
------------------------

After installation, run the initialization wizard:

.. code-block:: bash

   tenctl-init

This initializes SDN zones and cluster networking using settings from the config file. It uses:

- VLAN pool range (e.g., 100-200)
- Subnet allocation (e.g., 10.100.0.0/16 derived from ``BASE_SUBNET``)
- Default resource limits for tenants
- VyOS router integration (optional)
- Network SDN zone type

Review the configuration:

.. code-block:: bash

   cat /usr/local/share/tenctl/config/tenant.conf

You should see:

.. code-block:: bash

   # VLAN Configuration
   VLAN_START=100
   VLAN_END=999

   # Network Configuration
   BASE_SUBNET="10.100"

   # Default Resources
   DEFAULT_CPU_LIMIT=8
   DEFAULT_RAM_LIMIT=16384  # MB
   DEFAULT_STORAGE_LIMIT=500 # GB
