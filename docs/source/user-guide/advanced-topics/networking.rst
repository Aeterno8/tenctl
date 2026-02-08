Networking
==========

VLAN Allocation
---------------

VLANs are automatically allocated from a configured pool.

Configuration
~~~~~~~~~~~~~

Set VLAN pool in ``/usr/local/share/tenctl/config/tenant.conf``:

.. code-block:: bash

   VLAN_START=100
   VLAN_END=200

This allows 101 tenants (VLAN 100-200 inclusive).

Automatic Allocation
~~~~~~~~~~~~~~~~~~~~

By default, first available VLAN is assigned:

.. code-block:: bash

   tenctl-add -n "tenant_name" -c 8 -r 16384 -s 500 -e "admin@example.com"

Manual Assignment
~~~~~~~~~~~~~~~~~

Specify VLAN during creation:

.. code-block:: bash

   tenctl-add -n "tenant_name" --vlan 150 -c 8 -r 16384 -s 500 -e "admin@example.com"

Subnet Assignment
-----------------

Subnets are automatically allocated from the configured base range.

Configuration
~~~~~~~~~~~~~

.. code-block:: bash

   BASE_SUBNET="10.100"

Formula
~~~~~~~

Subnet = first available ``${BASE_SUBNET}.X.0/24``

Examples:

- 10.100.0.0/24
- 10.100.1.0/24
- 10.100.50.0/24

Manual Subnet
~~~~~~~~~~~~~

.. code-block:: bash

   tenctl-add -n "tenant_name" --subnet 192.168.100.0/24 -c 8 -r 16384 -s 500 -e "admin@example.com"

VyOS Integration
----------------

Configure VyOS router for L3 routing and NAT. Tenant VLAN and subnet configuration is applied during tenant creation when VyOS integration is enabled.

Setup
~~~~~

.. code-block:: bash

   tenctl-vyos configure --wan-ip 192.168.1.100 --wan-gw 192.168.1.1
   tenctl-vyos enable --wan-ip 192.168.1.100 --wan-gw 192.168.1.1

This configures:

- VLAN interface on VyOS
- Gateway IP address
- NAT rules for internet access
