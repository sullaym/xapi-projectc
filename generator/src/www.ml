open Files
open Types

type page = {
  name: string;
  title: string;
  filename: string;
  path: string;
  description: string;
  api: Interfaces.t;
}

(* Printable string of type *)
let rec html_of_t env =
  let open Type in
  let print txt = [ `Data txt ] in
  function
  | Basic b -> print (ocaml_of_basic b)
  | Struct (_, _) -> print ("struct  { ... }")
  | Variant (_, _) -> print ("variant { ... }")
  | Array t -> html_of_t env t @ (print " list")
  | Dict (key, v) -> print (Printf.sprintf "(%s * " (ocaml_of_basic key)) @ (html_of_t env v) @ (print ") list");
  | Name x ->
    let ident =
      if not(List.mem_assoc x env)
      then failwith (Printf.sprintf "Unable to find ident: %s" x)
      else List.assoc x env in
    let target = [ `Data ("#a-" ^ x) ] in
    let name = [ `Data (String.concat "/" ident.Ident.name) ] in
    <:html< <a href="$target$">$name$</a> >>
  | Unit -> print "unit"
  | Option x -> html_of_t env x @ (print " option")
  | Pair(a, b) -> html_of_t env a @ (print " * ") @ (html_of_t env b)
  | Custom c -> print c

(* Function inputs and outputs in a table *)
let of_args env args =
  let row_of_arg (is_in, arg) =
    let name = [ `Data arg.Arg.name ] in
    let direction = [ `Data (if is_in then "in" else "out") ] in
    let ty = html_of_t env arg.Arg.ty in
    let description = [ `Data arg.Arg.description ] in
  <:html<
    <tr>
      <td><code>$name$</code></td>
      <td>$direction$</td>
      <td><code>$ty$</code></td>
      <td>$description$</td>
    </tr>
  >> in
  <:html<
  <table width="100%">
  <thead>
    <tr>
      <th>Name</th>
      <th>Direction</th>
      <th>Type</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
    $List.concat (List.map row_of_arg args)$
  </tbody>
  </table>
  >>

let sidebar env x =
  let of_typedecl name_opt t =
    let ident = ident_of_type_decl env t in
    let target = [ `Data
                     (match name_opt with
                     | Some name -> Printf.sprintf "#a-%s-%s" name ident.Ident.id
                     | None -> Printf.sprintf "#a-%s" ident.Ident.id)]
    in
    let name = [ `Data t.TyDecl.name ] in
    <:html<
      <li><a href="$target$">$name$</a></li>
    >> in
  let of_method name m =
    let target = [ `Data (Printf.sprintf "#a-%s-%s" name m.Method.name) ] in
    let name = [ `Data m.Method.name ] in
    <:html<
      <li><a href="$target$">$name$</a></li>
    >> in
  let of_interface i =
    let name = [ `Data i.Interface.name ] in
    <:html<
      <li class="docs-nav-title">interface: $name$</li>
      $ List.concat (List.map (of_typedecl (Some i.Interface.name)) i.Interface.type_decls) $
      $ List.concat (List.map (of_method i.Interface.name) i.Interface.methods) $
    >> in
  <:html<
      <div class="large-3 medium-3 columns">
        <ul class="menu vertical">
          <li class="docs-nav-title">types</li>
          $List.concat (List.map (of_typedecl None) x.Interfaces.type_decls)$
          $List.concat (List.map of_interface x.Interfaces.interfaces)$
          <li class="docs-nav-title">exception</li>
          <li><a href="#a-exceptions">Exceptions</a></li>
        </ul>
      </div>
  >>

let of_struct_variant_fields all =
  let of_row (name, ty, descr) =
    let name = [ `Data name ] in
    let ty = [ `Data (Type.ocaml_of_t ty) ] in
    let description = [ `Data descr ] in
    <:html<
      <tr>
        <td><pre>$name$</pre></td>
        <td><pre>$ty$</pre></td>
        <td>$description$</td></tr>
    >> in
  <:html<
    <table width="100%">
      <thead>
        <tr>
          <th>Name</th>
          <th>Type</th>
          <th>Description</th>
        </tr>
      </thead>
      <tbody>
      $List.concat (List.map of_row all)$
      </tbody>
    </table>
  >>

let of_type_decl (env: 'a list) i_opt t =
  let ident = ident_of_type_decl env t in
  let anchor =
    match i_opt with
    | Some i -> [ `Data (Printf.sprintf "a-%s-%s" i.Interface.name ident.Ident.id) ]
    | None -> [`Data (Printf.sprintf "a-%s" ident.Ident.id) ] in
  let name = [ `Data t.TyDecl.name ] in
  let defn = [ `Data (Type.string_of_t ident.Ident.ty) ] in
  let description = [ `Data t.TyDecl.description ] in
  let common =
  <:html<
    <h4 id="$anchor$">type $name$ = $defn$</h4>
    <p> $description$ </p>
  >> in
  let rest = match ident.Ident.original_ty with
  | Type.Struct(hd, tl) ->
    <:html<
      <p>Members:</p>
    >> @ (of_struct_variant_fields (hd::tl))

  | Type.Variant(hd, tl) ->
    <:html<
      <p>Constructors:</p>
    >> @ (of_struct_variant_fields (hd::tl))
  | _ -> [] in
  common @ rest

let tabs_of env is i m =
  let mname = [ `Data m.Method.name ] in
  let hash_defn = [ `Data ("#defn-" ^ m.Method.name) ] in
  let hash_ocaml = [ `Data ("#ocaml-" ^ m.Method.name) ] in
  let hash_python = [ `Data ("#python-" ^ m.Method.name) ] in
  let id_tab = [ `Data ("tab-" ^ m.Method.name) ] in
  let id_defn = [ `Data ("defn-" ^ m.Method.name) ] in
  let id_ocaml = [ `Data ("ocaml-" ^ m.Method.name) ] in
  let id_python = [ `Data ("python-" ^ m.Method.name) ] in
  <:html<
    <ul class="tabs" data-tabs="" id="$id_tab$">
     <li class="tabs-title is-active"><a href="$hash_defn$" aria-selected="true">Definition</a></li>
     <li class="tabs-title"><a href="$hash_ocaml$">OCaml example</a></li>
     <li class="tabs-title"><a href="$hash_python$">Python example</a></li>
    </ul>
    <div class="tabs-content" data-tabs-content="$id_tab$">
      <div class="tabs-panel is-active" id="$id_defn$">
        $ of_args env ((List.map (fun m -> true, m) m.Method.inputs) @
                       (List.map (fun m -> false, m) m.Method.outputs)) $
      </div>
      <div class="tabs-panel" id="$id_ocaml$">
        <h4>Client</h4>
        $ Cow.Html.of_string (Ocaml.caml2html (Ocaml.example_stub env is i m |> Ocaml.string_of_ts)) $
        <h4>Server</h4>
        $ Cow.Html.of_string (Ocaml.caml2html (Ocaml.example_skeleton_user env is i m |> Ocaml.string_of_ts)) $
      </div>
      <div class="tabs-panel" id="$id_python$">
        <h4>Client</h4>
        <pre class="prettyprint lang-py">
        $[ `Data (Python.example_stub_user env i m |> Python.string_of_ts) ]$
        </pre>
        <h4>Server</h4>
        <pre class="prettyprint lang-py">
        $[ `Data (Python.example_skeleton_user env i m |> Python.string_of_ts) ]$
        </pre>
      </div>
    </div>
  >>

let of_method (env: 'a list) is i m =
  let anchor = [ `Data (Printf.sprintf "a-%s-%s" i.Interface.name m.Method.name) ] in
  let name = [ `Data m.Method.name ] in
  let description = [ `Data m.Method.description ] in
  <:html<
    <h3 id="$anchor$">$name$</h3>
    <p>$description$</p>
    $ tabs_of env is i m $
  >>

let of_interface (env: 'a list) is i =
  let anchor = [ `Data ("a-" ^ i.Interface.name) ] in
  let name = [ `Data i.Interface.name ] in
  let description = [ `Data i.Interface.description ] in
  <:html<
    <h2 id="$anchor$">$name$</h2>
    <p>$description$</p>
    $List.concat (List.map (of_type_decl env (Some i)) i.Interface.type_decls)$
    $List.concat (List.map (of_method env is i) i.Interface.methods)$
  >>

let of_exception env ts =
  let row_of t =
    let ident = ident_of_type_decl env t in
    let name = [ `Data (String.concat "/" ident.Ident.name) ] in
    let ty = [ `Data (Type.ocaml_of_t ident.Ident.original_ty) ] in
    let description = [ `Data ident.Ident.description ] in
    <:html<
      <tr>
        <td><pre>$name$</pre></td>
        <td><pre>$ty$</pre></td>
        <td>$description$</td>
      </tr>
    >> in
  <:html<
    <h3 id="a-exceptions">exceptions</h3>
    <table width="100%">
      <thead>
        <tr>
          <th>Name</th>
          <th>Type</th>
          <th>Description</th>
        </tr>
     </thead>
     <tbody>
       $List.concat (List.map row_of ts)$
     </tbody>
    </table>
  >>

let of_interfaces env x =
  let name = [ `Data x.Interfaces.name ] in
  let description = [ `Data x.Interfaces.description ] in
  <:html<
    <div class="row">

    $sidebar env x$

    <div class="large-9 medium-9 columns">
      <h1>$name$</h1>
      <p>$description$</p>
      $List.concat (List.map (of_type_decl env None) x.Interfaces.type_decls)$
      $List.concat (List.map (of_interface env x) x.Interfaces.interfaces)$
      $of_exception env x.Interfaces.exn_decls$
    </div>
    </div>
  >>

let to_string env x = Cow.Html.to_string (of_interfaces env x)

let topbar pages =
  let link_of_page page =
    let html = [ `Data (page.name ^ ".html") ] in
    let name = [ `Data page.name ] in
    <:html<
      <li><a href="$html$">$name$</a></li>
    >> in
<:html<
<div class="title-bar" data-responsive-toggle="main-menu" data-hide-for="medium">
  <button class="menu-icon" type="button" data-toggle=""></button>
  <div class="title-bar-title">Menu</div>
</div>

    <div class="top-bar" id="main-menu">
      <div class="top-bar-left">
	<ul class="menu" data-dropdown-menu="">
	  <li class="menu-text">SMAPIv3</li>
	</ul>
      </div>
      <div class="top-bar-right">
	<ul class="menu" data-responsive-menu="drilldown medium-dropdown">
	  <li class="has-submenu">
            <a href="features.html">Learn</a>
            <ul class="submenu menu vertical" data-submenu="">
              <li><a href="features.html">Features</a></li>
              <li><a href="concepts.html">Concepts</a></li>
              <li><a href="architecture.html">Architecture</a></li>
              <li><a href="faq.html">FAQ</a></li>
            </ul>
	  </li>
	  <li>
            <a href="#">Develop</a>
            <ul class="submenu menu vertical">
              $List.concat (List.map link_of_page pages)$
            </ul>
	  </li>
	  <li>
            <a href="#">Support</a>
            <ul class="submenu menu vertical">
              <li><a href="contact.html">Mailing list</a></li>
              <li><a href="contact.html">Issue tracker</a></li>
              <li><a href="contact.html">IRC</a></li>
            </ul>
	  </li>
	  <li class="active"><a href="getstarted.html">Get Started</a></li>
	</ul>
      </div>
    </div>
>>


let index_html oc pages =
  let header = <:html<
  <header>
    <div class="row">
      <div class="large-12 columns">
        <h1>Xapi storage interface</h1>
        <h3 class="subheader">An easy way to connect <a href="http://www.xenproject.org/developers/teams/xapi.html">Xapi</a> to any storage type.</h3>
        <hr/>
        <h2>Who is this for?</h2>
        <p>This is for anyone who has a storage system which is not supported
           by xapi out-of-the-box.</p>
      </div>
    </div>
    <div class="row">
      <div class="large-6 columns">
        <img src="img/your-bit-here.svg" alt="Your bit here"/>
      </div>
      <div class="large-6 columns">
        <p>This is also for anyone who wants to manage their
           storage in a customized way. If you can make your volumes appear
           as Linux block devices <i>or</i> you can refer to the volumes via
           URIs of the form <tt>iscsi://</tt> <tt>nfs://</tt> or <tt>rbd://</tt>then
           this documentation is for you.</p>
        <p><b>No Xapi or Xen specific knowledge
           is required.</b></p>
      </div>
    </div>
    <div class="row">
      <div class="large-12 columns panel callout">
        <h2>Status of this documentation</h2>
        <p>This documentation is a draft intended for discussion only.
           Please:</p>
        <ul>
          <li>view the <a href="https://github.com/djs55/xapi-storage/issues">issues on github</a></li> or
          <li>join the <a href="http://lists.xenproject.org/mailman/listinfo/xen-api">mailing list</a></li>
        </ul>
      </div>
    </div>
  </header>
  >> in
  print_file_to oc ("doc/header.html");
  output_string oc (Cow.Html.to_string (topbar pages));
  output_string oc (Cow.Html.to_string header);
  print_file_to oc ("doc/footer.html")

let placeholder_html oc pages body =
  let header = <:html<
    <div class="row">
      <div class="large-12 columns panel callout">
        <p>This is a placeholder</p>
      </div>
    </div>
  >> in
  print_file_to oc ("doc/header.html");
  output_string oc (Cow.Html.to_string (topbar pages));
  if Sys.file_exists body
  then print_file_to oc body
  else output_string oc (Cow.Html.to_string header);
  print_file_to oc ("doc/footer.html")

let page_of_api api = {
  name = api.Interfaces.name;
  title = api.Interfaces.title;
  path = "doc/" ^ api.Interfaces.name ^ ".html";
  filename = api.Interfaces.name ^ ".html";
  description = api.Interfaces.description;
  api = api;
}

let write apis =
  let pages = List.map page_of_api apis in

  List.iter
    (fun page ->
       with_output_file page.path
         (fun oc ->
            print_file_to oc ("doc/header.html");
            output_string oc (Cow.Html.to_string (topbar pages));
            let idents, api = Types.resolve_refs_in_api page.api in
            output_string oc (to_string idents api);
            print_file_to oc ("doc/footer.html")
         );
    ) pages;
  with_output_file "doc/index.html"
    (fun oc ->
       index_html oc pages
    );
  List.iter
    (fun placeholder ->
      let filename = Filename.concat "doc" placeholder in
      with_output_file filename
        (fun oc ->
          placeholder_html oc pages (filename ^ ".body")
        )
    ) [
      "contact.html";
      "concepts.html";
      "getstarted.html";
      "features.html";
      "faq.html";
      "learn.html";
      "architecture.html";
    ]
