guilemoduledir = $(datadir)/guile/site/3.0
guilemodule_DATA = module/sshfling.scm
pkgdatadir = $(datadir)/sshfling-guile
nobase_pkgdata_DATA = runtime/sshfling.py $(shell find runtime/templates -type f -print)
bin_SCRIPTS = bin/sshfling-guile
EXTRA_DIST = module/sshfling.scm.in bin/sshfling-guile.in \
  $(nobase_pkgdata_DATA) test/consumer.scm
