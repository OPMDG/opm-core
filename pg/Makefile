EXTENSION = opm_core
DATA = opm_core--2.1.sql \
	   opm_core--2.1--2.2.sql \
	   opm_core--2.2.sql

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
