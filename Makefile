# This Makefile ensures that the build is made out of source in a
# subdirectory called 'build' If it doesn't exist, it is created.
#
# This Makefile also contains delegation of the most common make commands
#
# If you have cmake installed you should be able to do:
#
#	make
#	make test
#	make install
#	make package
#
# That should build Cgreen in the build directory, run some tests,
# install it locally and generate a distributable package.

ifndef VERBOSE
MAKEFLAGS += --no-print-directory
endif

.PHONY:all
all: build-it

.PHONY:debug
debug:
	cmake -DCMAKE_BUILD_TYPE:string=Debug -S . -B build
	$(MAKE) -C build

.PHONY:test
test: build-it
	cd build; ctest

.PHONY:clean
clean: build/Makefile
	$(MAKE) -C build clean

.PHONY:package
package: build/Makefile
	$(MAKE) -C build package

.PHONY:install
install: build
ifeq ($(OS),Msys)
	# Thanks to https://stackoverflow.com/a/46027426/204658
	$(MAKE) -C build install DESTDIR=/
else
	$(MAKE) -C build install
endif

# This is kind of a hack to get a quicker and clearer feedback when
# developing Cgreen by allowing 'make unit'. Must be updated when new
# test libraries or output comparisons are added.

# Find out if 'uname -o' works, if it does - use it, otherwise use 'uname -s'
UNAMEOEXISTS=$(shell uname -o &>/dev/null; echo $$?)
ifeq ($(UNAMEOEXISTS),0)
  OS=$(shell uname -o)
else
  OS=$(shell uname -s)
endif

# Set prefix and suffix for shared libraries depending on platform
ifeq ($(OS),Darwin)
	LDPATH=DYLD_LIBRARY_PATH=$(PWD)/build/src
	PREFIX=lib
	SUFFIX=.dylib
else ifeq ($(OS),Cygwin)
	LDPATH=PATH=$(PWD)/build/src:"$$PATH"
	PREFIX=cyg
	SUFFIX=.dll
else ifeq ($(OS),Msys)
# This is for Msys "proper"
# TODO: handle Msys/Mingw32/64
	LDPATH=PATH=$(PWD)/build/src:"$$PATH"
	PREFIX=msys-
	SUFFIX=.dll
else
	LDPATH=LD_LIBRARY_PATH=$(PWD)/build/src
	PREFIX=lib
	SUFFIX=.so
endif

# Here are
#
# 1. tests linked into a library that we run as is
# 2. tests linked into a library that we run and compare its normalized output to expected output

# TODO: the diff_tools scripts determine prefix and extension by themselves
# Would be better if those were arguments, since we do it here anyway

# These "diff tools" also normalize the output using replacements
DIFF_TOOL=../../tools/cgreen_runner_output_diff
XML_DIFF_TOOL=../../tools/cgreen_xml_output_diff
DIFF_TOOL_ARGUMENTS = $(1)_tests \
	../../tests \
	$(1)_tests.expected

.PHONY: unit
unit: build-it
	cd build ; \
	$(LDPATH) tools/cgreen-runner -c `find tests -name $(PREFIX)cgreen_c_tests$(SUFFIX)` ; \
	r=$$((r + $$?)) ; \
	$(LDPATH) tools/cgreen-runner -c `find tests -name $(PREFIX)cgreen_cpp_tests$(SUFFIX)` ; \
	r=$$((r + $$?)) ; \
	$(LDPATH) tools/cgreen-runner -c `find tools -name $(PREFIX)cgreen_runner_tests$(SUFFIX)` ; \
	r=$$((r + $$?)) ; \
	cd tests ; \
	$(LDPATH) $(XML_DIFF_TOOL) $(call DIFF_TOOL_ARGUMENTS,xml_output) ; \
	r=$$((r + $$?)) ; \
	$(LDPATH) $(DIFF_TOOL) $(call DIFF_TOOL_ARGUMENTS,assertion_messages) ; \
	r=$$((r + $$?)) ; \
	$(LDPATH) $(DIFF_TOOL) $(call DIFF_TOOL_ARGUMENTS,mock_messages) ; \
	r=$$((r + $$?)) ; \
	$(LDPATH) $(DIFF_TOOL) $(call DIFF_TOOL_ARGUMENTS,constraint_messages) ; \
	r=$$((r + $$?)) ; \
	$(LDPATH) $(DIFF_TOOL) $(call DIFF_TOOL_ARGUMENTS,custom_constraint_messages) ; \
	r=$$((r + $$?)) ; \
	$(LDPATH) $(DIFF_TOOL) $(call DIFF_TOOL_ARGUMENTS,ignore_messages) ; \
	r=$$((r + $$?)) ; \
	$(LDPATH) CGREEN_PER_TEST_TIMEOUT=1 $(DIFF_TOOL) $(call DIFF_TOOL_ARGUMENTS,failure_messages) ; \
	r=$$((r + $$?)) ; \
	exit $$r

.PHONY: doc
doc: build
	cmake -DCGREEN_WITH_HTML_DOCS:bool=TRUE -S . -B build
	cmake --build build
	cmake -DCGREEN_WITH_HTML_DOCS:bool=False -S . -B build
	echo open $(PWD)/build/doc/cgreen-guide-en.html

pdf: build
	cmake -DCGREEN_WITH_PDF_DOCS:bool=TRUE -S . -B build
	cmake --build build
	cmake -DCGREEN_WITH_PDF_DOCS:bool=FALSE -S . -B build
	echo open $(PWD)/build/doc/cgreen-guide-en.pdf

chunked: doc
	asciidoctor-chunker build/doc/cgreen-guide-en.html -o docs
	echo open $(PWD)/docs/index.html

.PHONY:valgrind
valgrind: build-it
	@echo -n "Running all tests under Valgrind "
	@> valgrind.log
	@for lib in `ls build/tests/$(PREFIX)*_tests$(SUFFIX)` ; \
	do \
		echo -n "." ; \
		LD_LIBRARY_PATH=build/src valgrind --leak-check=full build/tools/cgreen-runner $$lib >> valgrind.log 2>&1 ; \
	done
	@echo
	grep --with-filename --line-number " lost: " valgrind.log | grep -v " 0 bytes" ; \
	if [ $$? -eq 1 ] ; then echo "Nothing lost" ; fi



############# Internal
build build/Makefile:
ifeq ($(OS),Darwin)
#	cmake -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -S . -B build
	cmake -S . -B build
else
	cmake -S . -B build
endif

.PHONY:build-it
build-it: build
	$(MAKE) -C build

.SILENT:
