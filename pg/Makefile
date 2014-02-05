EXTENSION = opm_core
DATA = opm_core--1.0.sql opm_core--1.0--1.1.sql \
	opm_core--1.1--1.0.sql opm_core--1.1.sql

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
