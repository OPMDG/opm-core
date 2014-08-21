EXTENSION = opm_core
DATA = opm_core--2.2.sql \
	   opm_core--2.2--2.3.sql \
	   opm_core--2.3.sql \
	   opm_core--2.3--2.4.sql \
	   opm_core--2.4.sql

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
