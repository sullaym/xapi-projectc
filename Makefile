
idl: types.cmx smapiv2.cmx xenops.cmx memory.cmx main.cmx
	ocamlfind ocamlopt -package xmlm,yojson,stdext -linkpkg -g -o idl types.cmx smapiv2.cmx xenops.cmx memory.cmx main.cmx

toplevel: types.cmo smapiv2.cmo xenops.cmo memory.cmo
	ocamlfind ocamlmktop -thread -package xmlm,yojson,stdext -linkpkg -g -o toplevel types.cmo smapiv2.cmo xenops.cmo memory.cmo

%.cmx: %.ml
	ocamlfind ocamlopt -package xmlm,yojson,stdext -c -g $<

%.cmo: %.ml
	ocamlfind ocamlc -package xmlm,yojson,stdext -c -g $<

.PHONY: install
install: idl
	./idl

.PHONY: clean
clean:
	rm -f *.cmx *.cmo idl toplevel
