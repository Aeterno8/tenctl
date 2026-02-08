Monitoring and Auditing
=======================

Health Checks
-------------

Verify tenant configuration:

.. code-block:: bash

   tenctl-health -n tenant_name

Checks performed:

- ✓ System dependencies (pvesh, jq, flock, vzdump)
- ✓ Proxmox cluster status and connectivity
- ✓ SDN zone configuration
- ✓ VLAN/subnet allocation and conflicts
- ✓ Tenant configuration integrity
- ✓ Resource pool, user/group, and ACL checks
- ✓ Orphaned resources detection

Verbose output:

.. code-block:: bash

   tenctl-health -v -n tenant_name

JSON output (for automation):

.. code-block:: bash

   tenctl-health -j

Audit Logs
----------

View tenant audit trail:

.. code-block:: bash

   tenctl-audit -n tenant_name

Logs all operations:

- Tenant creation
- Modifications
- Suspensions/resumes
- Removals

System-wide audit:

.. code-block:: bash

   tenctl-audit

JSON output:

.. code-block:: bash

   tenctl-audit --json

Best Practices
==============

**Start Conservative**
  Begin with lower limits and increase as needed with ``tenctl-modify``.

**Monitor Regularly**
  Use ``tenctl-usage`` to track consumption and identify growth trends.

**Review Health**
  Run ``tenctl-health`` regularly to ensure configuration integrity.

**Check Audit Logs**
  Review ``tenctl-audit`` for compliance and troubleshooting.

**Suspend Instead of Remove**
  Use ``tenctl-suspend`` for temporary issues instead of removing tenants.
