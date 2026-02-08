Configuration Reference
=======================

Complete reference for ``/usr/local/share/tenctl/config/tenant.conf``.

Configuration File Location
----------------------------

The main configuration file is located at::

   /usr/local/share/tenctl/config/tenant.conf

This file contains global settings for the multi-tenant system.

VLAN Configuration
------------------

VLAN_START
~~~~~~~~~~

**Type:** Integer

**Default:** ``100``

**Description:** Starting VLAN ID for tenant allocation pool.

**Example:**

.. code-block:: bash

   VLAN_START=100

VLAN_END
~~~~~~~~

**Type:** Integer

**Default:** ``999``

**Description:** Ending VLAN ID for tenant allocation pool.

**Valid Range:** VLAN_START to 4094 (maximum VLAN ID)

**Example:**

.. code-block:: bash

   VLAN_END=999

**Note:** Total available VLANs = VLAN_END - VLAN_START + 1

Network Configuration
---------------------

BASE_SUBNET
~~~~~~~~~~~

**Type:** String (IP prefix)

**Default:** ``"10.100"``

**Description:** Base subnet prefix for tenant networks. Each tenant receives a /24 subnet.

**Example:**

.. code-block:: bash

   BASE_SUBNET="10.100"

This results in subnets like:

- Tenant 1: 10.100.0.0/24
- Tenant 2: 10.100.1.0/24
- Tenant N: 10.100.N-1.0/24

NETWORK_BRIDGE
~~~~~~~~~~~~~~

**Type:** String

**Default:** ``"vmbr0"``

**Description:** Default Proxmox network bridge for VLAN configuration.

**Example:**

.. code-block:: bash

   NETWORK_BRIDGE="vmbr0"

Storage Configuration
---------------------

TENANT_CONFIG_DIR
~~~~~~~~~~~~~~~~~

**Type:** String (path)

**Default:** ``"/etc/pve/tenants"``

**Description:** Directory for tenant configuration files. Located in pmxcfs for automatic cluster synchronization.

**Example:**

.. code-block:: bash

   TENANT_CONFIG_DIR="/etc/pve/tenants"

**Note:** This directory is automatically synchronized across cluster nodes via pmxcfs.

Resource Defaults
-----------------

DEFAULT_CPU_LIMIT
~~~~~~~~~~~~~~~~~

**Type:** Integer

**Default:** ``8``

**Description:** Default CPU core limit for new tenants.

**Example:**

.. code-block:: bash

   DEFAULT_CPU_LIMIT=8

DEFAULT_RAM_LIMIT
~~~~~~~~~~~~~~~~~

**Type:** Integer (MB)

**Default:** ``16384`` (16 GB)

**Description:** Default RAM limit for new tenants in megabytes.

**Example:**

.. code-block:: bash

   DEFAULT_RAM_LIMIT=16384  # 16 GB

**Conversion:**

- 1 GB = 1024 MB
- 8 GB = 8192 MB
- 16 GB = 16384 MB
- 32 GB = 32768 MB

DEFAULT_STORAGE_LIMIT
~~~~~~~~~~~~~~~~~~~~~

**Type:** Integer (GB)

**Default:** ``500``

**Description:** Default storage limit for new tenants in gigabytes.

**Example:**

.. code-block:: bash

   DEFAULT_STORAGE_LIMIT=500  # 500 GB

**Note:** Resource limits are monitored by the ``tenctl-watcher`` systemd service.

SDN Configuration
-----------------

SDN_ZONE_TYPE
~~~~~~~~~~~~~

**Type:** String (enum)

**Default:** ``"vxlan"``

**Valid Values:**

- ``"vlan"`` - VLAN zone (single-node or managed switch)
- ``"vxlan"`` - VXLAN zone (multi-node overlay)
- ``"simple"`` - Simple zone (untagged)

**Description:** SDN zone type for Proxmox network virtualization.

**Example:**

.. code-block:: bash

   SDN_ZONE_TYPE="vxlan"

**Recommendations:**

- Single-node: Use ``"vlan"``
- Multi-node cluster: Use ``"vxlan"``
- Basic setup: Use ``"simple"``

SDN_ZONE_NAME
~~~~~~~~~~~~~

**Type:** String

**Default:** ``"tenants"``

**Max Length:** 8 characters (Proxmox API limitation)

**Description:** Name of the SDN zone.

**Example:**

.. code-block:: bash

   SDN_ZONE_NAME="tenants"

VXLAN_PORT
~~~~~~~~~~

**Type:** Integer

**Default:** ``4789``

**Description:** UDP port for VXLAN encapsulation (only used if SDN_ZONE_TYPE="vxlan").

**Example:**

.. code-block:: bash

   VXLAN_PORT=4789

**Note:** Standard VXLAN port is 4789.

Permissions Configuration
-------------------------

TENANT_ADMIN_ROLE
~~~~~~~~~~~~~~~~~

**Type:** String

**Default:** ``"PVEPoolAdmin"``

**Description:** Proxmox role assigned to tenant admin users.

**Example:**

.. code-block:: bash

   TENANT_ADMIN_ROLE="PVEPoolAdmin"

**Available Roles:**

- ``PVEPoolAdmin`` - Pool administrator (recommended)
- ``PVEPoolUser`` - Pool user (read-only)
- Custom role created in Proxmox

Logging Configuration
---------------------

LOG_DIR
~~~~~~~

**Type:** String (path)

**Default:** ``"/var/log/tenctl"``

**Description:** Directory for tenant management logs.

**Example:**

.. code-block:: bash

   LOG_DIR="/var/log/tenctl"

**Log Files:**

- ``tenant-management.log`` - All operations and audit events

Email Notifications
-------------------

EMAIL_NOTIFICATIONS_ENABLED
~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Type:** Boolean

**Default:** ``true``

**Description:** Enable email notifications for tenant operations.

**Example:**

.. code-block:: bash

   EMAIL_NOTIFICATIONS_ENABLED=true

SMTP_ENDPOINT
~~~~~~~~~~~~~

**Type:** String

**Default:** ``"Gmail"``

**Description:** Name of SMTP endpoint configured in Proxmox ``/etc/pve/notifications.cfg``.

**Example:**

.. code-block:: bash

   SMTP_ENDPOINT="Gmail"

**Note:** Configure SMTP in Proxmox VE first:

1. Navigate to Datacenter → Notifications
2. Add SMTP endpoint
3. Use the name here

VyOS Router Configuration
--------------------------

VYOS_ENABLED
~~~~~~~~~~~~

**Type:** Boolean

**Default:** ``true``

**Description:** Enable VyOS router integration for L3 routing and NAT.

**Example:**

.. code-block:: bash

   VYOS_ENABLED=true

VYOS_NODE
~~~~~~~~~

**Type:** String

**Default:** ``"pve3"``

**Description:** Proxmox node name where VyOS VM is running.

**Example:**

.. code-block:: bash

   VYOS_NODE="pve3"

VYOS_VMID
~~~~~~~~~

**Type:** Integer

**Default:** ``900``

**Description:** VM ID of the VyOS router.

**Example:**

.. code-block:: bash

   VYOS_VMID="900"

VYOS_SSH_USER
~~~~~~~~~~~~~

**Type:** String

**Default:** ``"vyos"``

**Description:** SSH username for VyOS router.

**Example:**

.. code-block:: bash

   VYOS_SSH_USER="vyos"

**Note:** Default VyOS username is ``vyos``.

VYOS_IP
~~~~~~~

**Type:** String (IP address)

**Default:** ``"192.168.1.6"``

**Description:** Management IP address of VyOS router.

**Example:**

.. code-block:: bash

   VYOS_IP="192.168.1.6"

VYOS_WAN_INTERFACE
~~~~~~~~~~~~~~~~~~

**Type:** String

**Default:** ``"eth0"``

**Description:** WAN interface on VyOS router.

**Example:**

.. code-block:: bash

   VYOS_WAN_INTERFACE="eth0"

VYOS_LAN_INTERFACE
~~~~~~~~~~~~~~~~~~

**Type:** String

**Default:** ``"eth1"``

**Description:** LAN interface on VyOS for tenant VLANs.

**Example:**

.. code-block:: bash

   VYOS_LAN_INTERFACE="eth1"

VYOS_WAN_IP
~~~~~~~~~~~

**Type:** String (IP address)

**Default:** ``"192.168.1.6"``

**Description:** WAN IP address on VyOS router.

**Example:**

.. code-block:: bash

   VYOS_WAN_IP="192.168.1.6"

VYOS_WAN_GATEWAY
~~~~~~~~~~~~~~~~

**Type:** String (IP address)

**Default:** ``"192.168.1.1"``

**Description:** WAN gateway for VyOS router.

**Example:**

.. code-block:: bash

   VYOS_WAN_GATEWAY="192.168.1.1"

Configuration Examples
----------------------

Minimal Configuration
~~~~~~~~~~~~~~~~~~~~~

Basic setup for single-node Proxmox:

.. code-block:: bash

   # VLAN Configuration
   VLAN_START=100
   VLAN_END=200

   # Network Configuration
   BASE_SUBNET="10.100"
   NETWORK_BRIDGE="vmbr0"

   # Storage
   TENANT_CONFIG_DIR="/etc/pve/tenants"

   # Defaults
   DEFAULT_CPU_LIMIT=4
   DEFAULT_RAM_LIMIT=8192
   DEFAULT_STORAGE_LIMIT=200

   # SDN
   SDN_ZONE_TYPE="vlan"
   SDN_ZONE_NAME="tenants"

   # Permissions
   TENANT_ADMIN_ROLE="PVEPoolAdmin"

   # Logging
   LOG_DIR="/var/log/tenctl"

   # Email
   EMAIL_NOTIFICATIONS_ENABLED=false

   # VyOS
   VYOS_ENABLED=false

Multi-Node Cluster Configuration
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Configuration for multi-node cluster with VXLAN:

.. code-block:: bash

   # VLAN Configuration
   VLAN_START=100
   VLAN_END=500

   # Network Configuration
   BASE_SUBNET="10.100"
   NETWORK_BRIDGE="vmbr0"

   # SDN with VXLAN
   SDN_ZONE_TYPE="vxlan"
   SDN_ZONE_NAME="tenants"
   VXLAN_PORT=4789

   # Higher defaults for enterprise
   DEFAULT_CPU_LIMIT=16
   DEFAULT_RAM_LIMIT=32768
   DEFAULT_STORAGE_LIMIT=1000

   # Enable notifications
   EMAIL_NOTIFICATIONS_ENABLED=true
   SMTP_ENDPOINT="Company-SMTP"

   # VyOS integration
   VYOS_ENABLED=true
   VYOS_NODE="pve1"
   VYOS_VMID="900"
   VYOS_IP="192.168.1.10"

Best Practices
--------------

VLAN Planning
~~~~~~~~~~~~~

- Reserve ranges for different purposes (e.g., 100-299 production, 300-499 development)
- Don't use VLANs below 10 (often reserved for management)
- Document VLAN allocations

Resource Planning
~~~~~~~~~~~~~~~~~

- Set conservative defaults
- Monitor actual usage to adjust limits
- Plan for growth (increase VLAN_END as needed)

Security
~~~~~~~~

- Restrict access to configuration file::

     chmod 600 /usr/local/share/tenctl/config/tenant.conf

- Use strong VyOS credentials
- Enable email notifications for audit trail

Cluster Configuration
~~~~~~~~~~~~~~~~~~~~~

- Use VXLAN for multi-node setups
- Ensure consistent configuration across nodes
- Test failover scenarios

Validating Configuration
------------------------

After modifying configuration, validate:

.. code-block:: bash

   # Test tenant creation
   tenctl-add -n "test_tenant" -c 4 -r 8192 -s 100 -e "test@example.com"

   # Verify in Proxmox UI
   # Check resource pool, user group, permissions

   # Clean up test
   tenctl-remove -n test_tenant

See Also
--------

- :doc:`operations` - Operations and maintenance procedures
- :doc:`../getting-started/index` - Getting started guide
