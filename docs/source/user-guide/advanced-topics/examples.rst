Real-World Examples
===================

Web Hosting Provider
--------------------

Create isolated environments for multiple customers:

.. code-block:: bash

   # Small business
   tenctl-add -n "companyA" -c 4 -r 8192 -s 200 -e "admin@companya.com"

   # Medium business
   tenctl-add -n "contoso" -c 8 -r 16384 -s 500 -e "it@contoso.com"

   # Enterprise client
   tenctl-add -n "fabrikam" -c 32 -r 65536 -s 2000 -e "ops@fabrikam.com"

Development Environments
------------------------

Separate dev, staging, production:

.. code-block:: bash

   tenctl-add -n "project_dev" -c 4 -r 8192 -s 100 -e "dev@company.com"
   tenctl-add -n "project_staging" -c 8 -r 16384 -s 200 -e "dev@company.com"
   tenctl-add -n "project_prod" -c 16 -r 32768 -s 1000 -e "ops@company.com"

Temporary Tenant
----------------

Create, use, and remove:

.. code-block:: bash

   # Create for demo
   tenctl-add -n "temp_demo" -c 4 -r 8192 -s 100 -e "demo@example.com"

   # Use for testing...

   # Clean up
   tenctl-remove -n temp_demo

Resource Scaling
----------------

Scale resources as tenant grows:

.. code-block:: bash

   # Initial creation
   tenctl-add -n "startup" -c 4 -r 8192 -s 200 -e "admin@startup.com"

   # 6 months later, scale up
   tenctl-modify -n startup -c 16 -r 32768 -s 1000
