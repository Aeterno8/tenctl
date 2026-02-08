User Guide
==========

Complete guide to using Tenctl for tenant management.

.. toctree::
   :maxdepth: 2

   tenant-management/index
   advanced-topics/index

Command Structure
-----------------

Tenctl uses Git-style subcommands and can be invoked via the main entrypoint or standalone binaries::

   tenctl <command> [options]
   tenctl-<command> [options]

Global Options
~~~~~~~~~~~~~~

There are no universal flags supported by every subcommand. Common patterns:

``--help``
   Display command help (supported by most commands)

``tenctl --version``
   Show version information for the main entrypoint

``--verbose``
   Enable verbose output on commands that support it (``-v`` is available for some commands like ``tenctl-health`` and ``tenctl-usage``)

Exit Codes
----------

Exit codes are not standardized across all commands. In practice:

- ``0`` - Success
- ``1`` - General error (most failures)
