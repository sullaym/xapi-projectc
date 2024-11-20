
default: build

.PHONY: build
build:
	(cd generator; make)
	mkdir -p ocaml/examples
	mkdir -p python/xapi/storage/api
	./generator/main.native
	make -C ocaml
	make -C python

.PHONY: html
html: build
	./generator/main.native -html
	rsync -av ./doc/static/ ./doc/gen/

.PHONY: install
install:
	make -C ocaml install
	make -C python install

.PHONY: uninstall
uninstall:
	make -C ocaml uninstall
	make -C python uninstall

.PHONY: reinstall
reinstall:
	make -C ocaml reinstall
	make -C python reinstall

.PHONY: clean
clean:
	make -C generator clean
	make -C ocaml clean
	make -C python clean
