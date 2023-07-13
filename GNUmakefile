# On-the-side GNUmakefile contributed by https://github.com/SirNickolas with a
# few minor c-blake & CyberTailor updates.  `gmake -j$(nproc)` runs & checks all
# tests.  `gmake a='...'` allows to pass additional flags to the Nim compiler.
# Also useful to clean up test programs via `gmake clean`.

# Run `gmake V=1` for verbose output
V := 0
# Run `gmake J=$(nproc)` (or `J=0`) for higher nim c --parallelBuild:jobs
J := 1
AT_0 := @
AT_1 :=
AT := $(AT_$V)

DIFF ?= diff # DIFF='diff -u' gmake | gmake DIFF='diff --color=auto' | etc.
SED ?= sed

.PHONY: test clean clean_cache
export COLUMNS := 80
export CLIGEN_WIDTH := 80
export CLIGEN := /dev/null

NIM := $(or $(nim),nim)
NIM_BACKEND := $(or $(BE),c)

NIM_FLAGS := \
	--hints:off --warning:all:off --warning:User:on --colors:off\
	--parallelBuild:$J $a
NIM_CACHE := $(HOME)/.cache/nim

TESTS_OUT := $(patsubst %.nim,%.out,$(wildcard test/[A-Z]*.nim))
TESTS_TOP_LVL_OUT := $(patsubst %,test/%TopLvl.out,\
	FullyAutoMulti MultMultMult MultiMulti PassValuesMulti QualifiedMulti\
	RangeTypes SubScope)
OUT := test/out

test: $(OUT)

clean:
	$(AT)rm -f -- $(TESTS_OUT:.out=) $(TESTS_OUT) $(TESTS_TOP_LVL_OUT) $(OUT)

clean_cache:
	$(AT)rm -rf -- '$(NIM_CACHE)'/*

$(TESTS_OUT): %.out: %.nim clean_cache
	$(AT)$(NIM) $(NIM_BACKEND) --nimcache:'$(NIM_CACHE)/cache-$(<:.nim=)' \
		$(NIM_FLAGS) --run $< --help > $@ 2>&1

$(TESTS_TOP_LVL_OUT): %TopLvl.out: %.out
	$(AT)./$(<:.out=) help > $@ 2>&1

$(OUT): $(TESTS_OUT) $(TESTS_TOP_LVL_OUT)
	$(AT){ \
	set -eu; \
	tail -n+1 -- $(sort $^) | $(SED) \
		-e 's|.*/cligen.nim(|cligen.nim(|g' \
		-e 's|.*/cligen/|cligen/|g' \
		-e 's|.*/test/|test/|g' > $@; \
	rm -f -- $^; \
	$(DIFF) -- test/ref $@; \
	}
