# On-the-side GNUmakefile contributed by https://github.com/SirNickolas with a
# few minor c-blake updates.  `gmake -j$(nproc)` runs & checks all tests.
# `gmake a='...'` allows to pass additional flags to the Nim compiler.  Also
# useful to clean up test programs via `gmake clean`.

DIFF ?= diff # DIFF='diff -u' gmake | gmake DIFF='diff --color=auto' | etc.

.PHONY: test clean clean_cache
export COLUMNS := 80
export CLIGEN_WIDTH := 80
export CLIGEN := /dev/null

NIM := $(or $(nim),nim)
NIM_BACKEND := $(or $(BE),c)

#XXX I do not know why the warning push in the code fails to suppress.
NIM_FLAGS := --warning[ObservableStores]:off --warning[Deprecated]:off

ifeq ($(shell $(NIM) c $(NIM_FLAGS) /dev/null 2>&1 | \
		grep -q 'unknown warning:'; echo $$?),0)
	NIM_FLAGS :=
endif
NIM_FLAGS += --verbosity:1 --hint[Processing]:off --hint[SuccessX]=off $a
NIM_CACHE := $(HOME)/.cache/nim

TESTS_OUT := $(patsubst %.nim,%.out,$(wildcard test/[A-Z]*.nim))
TESTS_TOP_LVL_OUT := $(patsubst %,test/%TopLvl.out,\
	FullyAutoMulti MultiMulti RangeTypes)
OUT := test/out

test: $(OUT)

clean:
	@rm -f -- $(TESTS_OUT:.out=) $(TESTS_OUT) $(TESTS_TOP_LVL_OUT) $(OUT)

clean_cache:
	@rm -rf -- '$(NIM_CACHE)'/*

$(TESTS_OUT): %.out: %.nim clean_cache
	@$(NIM) $(NIM_BACKEND) --nimcache:'$(NIM_CACHE)/cache-$(<:.nim=)' \
		$(NIM_FLAGS) --run $< --help 2>&1 | grep -v '\<CC: ' > $@

$(TESTS_TOP_LVL_OUT): %TopLvl.out: %.out
	@./$(<:.out=) help > $@ 2>&1

$(OUT): $(TESTS_OUT) $(TESTS_TOP_LVL_OUT)
	@{ \
	set -eu; \
	head -n900 -- $(sort $^) | sed \
		-e '/^Hint: / d' \
		-e 's@.*/cligen.nim(@cligen.nim(@' \
		-e 's@.*/cligen/@cligen/@' \
		-e 's@.*/test/@test/@' > $@; \
	rm -f -- $^; \
	$(DIFF) -- test/ref $@; \
	}
