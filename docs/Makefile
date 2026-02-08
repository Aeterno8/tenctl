# Minimal makefile for Sphinx documentation
#

# You can set these variables from the command line, and also
# from the environment for the first two.
SPHINXOPTS    ?=
SPHINXBUILD   ?= sphinx-build
SOURCEDIR     = source
BUILDDIR      = build
SCRIPTSDIR    = scripts
LOCALEDIR     = locale

# Put it first so that "make" without argument is like "make help".
help:
	@$(SPHINXBUILD) -M help "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)

.PHONY: help Makefile clean html gettext update-po build-sr build-all

# Build HTML documentation
clean:
	@$(SPHINXBUILD) -M clean "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)

html:
	@$(SPHINXBUILD) -b html "$(SOURCEDIR)" "$(BUILDDIR)/html" $(SPHINXOPTS) $(O)
	@echo "English documentation built in $(BUILDDIR)/html"

# i18n targets
gettext:
	@echo "Extracting translatable strings..."
	@$(SPHINXBUILD) -b gettext "$(SOURCEDIR)" "$(BUILDDIR)/gettext" $(SPHINXOPTS) $(O)
	@echo "Translation templates (.pot files) generated in $(BUILDDIR)/gettext"

update-po: gettext
	@echo "Updating Serbian translation files..."
	@sphinx-intl update -p "$(BUILDDIR)/gettext" -l sr
	@echo "Fixing .po file headers..."
	@python3 $(SCRIPTSDIR)/fix-po-headers.py
	@echo "Serbian .po files updated in $(LOCALEDIR)/sr/LC_MESSAGES/"

build-sr: update-po
	@echo "Building Serbian documentation..."
	@$(SPHINXBUILD) -b html -D language=sr "$(SOURCEDIR)" "$(BUILDDIR)/html-sr" $(SPHINXOPTS) $(O)
	@echo "Serbian documentation built in $(BUILDDIR)/html-sr"

build-all: html build-sr
	@echo "All language versions built successfully"

# Catch-all target: route all unknown targets to Sphinx using the new
# "make mode" option.  $(O) is meant as a shortcut for $(SPHINXOPTS).
%: Makefile
	@$(SPHINXBUILD) -M $@ "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)
