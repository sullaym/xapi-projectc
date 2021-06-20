
let ( |> ) f g = g f

module Type = struct
    (** Subset of dbus types which we'll use *)

  type basic =
    | Int64
    | String
    | Double
    | Boolean
  let basic = [
    Int64, "x";
    String, "s";
    Double, "d";
    Boolean, "b";
  ]
  let string_of_basic x = List.assoc x basic
  let basic_of_string x =
    let basic' = List.map (fun (x, y) -> y, x) basic in
    if List.mem_assoc x basic'
    then Some (List.assoc x basic')
    else None
  let ocaml_of_basic = function
    | Int64 -> "int64"
    | String -> "string"
    | Double -> "float"
    | Boolean -> "bool"

  type t =
    | Basic of basic
    | Struct of (string * t) * ((string * t) list)
    | Array of t
    | Dict of basic * t

  let rec string_of_t = function
    | Basic b -> string_of_basic b
    | Struct ((_, h), tl) -> Printf.sprintf "(%s%s)" (string_of_t h) (String.concat "" (List.map string_of_t (List.map snd tl)))
    | Array x -> Printf.sprintf "a%s" (string_of_t x)
    | Dict (k, v) -> Printf.sprintf "a{%s%s}" (string_of_basic k) (string_of_t v)
  let rec ocaml_of_t = function
    | Basic b -> ocaml_of_basic b
    | Struct (_, _) -> "XXX"
    | Array t -> ocaml_of_t t ^ " list"
    | Dict (key, v) -> Printf.sprintf "(%s * %s) list" (ocaml_of_basic key) (ocaml_of_t v)

  type ts = t list

end

module Arg = struct
  type t = {
    name: string;
    description: string;
    ty: Type.t;
  }
end

module Method = struct
  type t = {
    name: string;
    description: string;
    inputs: Arg.t list;
    outputs: Arg.t list;
  }    
end

module Interface = struct
  type t = {
    name: string;
    description: string;
    methods: Method.t list;
  }
end

module Interfaces = struct
  type t = {
    name: string;
    description: string;
    interfaces: Interface.t list;
  }
end

let to_rpclight x =
  let open Format in
      let of_method m =
	let of_args name args =
	  printf "@[type %s = {@." name;
	  List.iter
	    (fun { Arg.name = name; ty = ty } ->
	      printf "@[%s@ :@ %s;@.@]" name (Type.ocaml_of_t ty) 
	    ) args;
	  printf "@.}@.@]" in
	of_args (m.Method.name ^ "_inputs") m.Method.inputs;
	of_args (m.Method.name ^ "_outputs") m.Method.outputs;
	printf "@[external %s: %s_inputs -> %s_outputs = \"\"@.@]" m.Method.name m.Method.name m.Method.name;
	printf "@[(** %s *)@.@]" m.Method.description
      in
      let of_interface i =
	printf "@[module %s = struct@." i.Interface.name;
	printf "(* %s *)@." i.Interface.description;
	List.iter of_method i.Interface.methods;
	printf "end@.@]" in
      let of_interfaces i =
	printf "@[(* %s *)@." i.Interfaces.description;
	List.iter of_interface i.Interfaces.interfaces;
	printf "@.@]"
      in
      of_interfaces x

let to_json x =
  let of_arg_list args =
    `Assoc (List.map (fun arg -> arg.Arg.name, `String (Type.string_of_t arg.Arg.ty)) args) in
  let of_interface i =
    `Assoc [
      "name", `String i.Interface.name;
      "description", `String i.Interface.description;
      "methods", 
      `List (List.map
	       (fun m ->
		 `Assoc [
		   "name", `String m.Method.name;
		   "inputs", of_arg_list m.Method.inputs;
		   "outputs", of_arg_list m.Method.outputs;
		 ]
	       ) i.Interface.methods)
    ] in
  let of_interfaces i =
    `Assoc [
      "name", `String i.Interfaces.name;
      "description", `String i.Interfaces.description;
      "interfaces", `List (List.map of_interface i.Interfaces.interfaces)
    ] in
  let json = of_interfaces x in
  Yojson.Basic.to_string json

let to_html x =
  let open Xmlm in
      let buffer = Buffer.create 128 in
      let output = Xmlm.make_output ~nl:true ~indent:(Some 4) (`Buffer buffer) in
      Xmlm.output output (`Dtd None);
      let wrap name body =
	Xmlm.output output (`El_start (("", name), []));
	Xmlm.output output (`Data body);
	Xmlm.output output (`El_end) in
      let h1 = wrap "h1" in
      let h2 = wrap "h2" in
      let h3 = wrap "h3" in
      let td = wrap "td" in
      let wrapf name items =
	Xmlm.output output (`El_start (("", name), []));
	items ();
	Xmlm.output output (`El_end) in
      let th = wrapf "th" in
      let tr = wrapf "tr" in
      let p = wrap "p" in

      let of_args args =
	Xmlm.output output (`El_start (("", "div"), [ ("", "class"), "alert alert-info" ]));
	Xmlm.output output (`El_start (("", "table"), [ ("", "class"), "table table-striped" ]));
	th (fun () -> td "Type"; td "Description");
	List.iter
	  (fun arg ->
	    tr (fun () -> td arg.Arg.name; td (Type.ocaml_of_t arg.Arg.ty); td arg.Arg.description);
	  ) args;
	Xmlm.output output (`El_end);
	Xmlm.output output (`El_end) in

      Xmlm.output output (`El_start (("", "div"), [ ("", "class"), "container" ]));
      h1 x.Interfaces.name;
      p x.Interfaces.description;
      List.iter
	(fun i ->
	  h2 i.Interface.name;
	  p i.Interface.description;
	  List.iter
	    (fun m ->
	      h3 m.Method.name;
	      p m.Method.description;
	      Buffer.add_string buffer
"
          <ul id=\"tab\" class=\"nav nav-tabs\">
            <li class=\"active\"><a href=\"#defn\" data-toggle=\"tab\">Definition</a></li>
            <li><a href=\"#dbus\" data-toggle=\"tab\">DBUS XML</a></li>
            <li><a href=\"#ocaml\" data-toggle=\"tab\">ocaml</a></li>
          </ul>
          <div id=\"myTabContent\" class=\"tab-content\">
            <div class=\"tab-pane fade in active\" id=\"defn\">
              <p>Raw denim you probably haven't heard of them jean shorts Austin. Nesciunt tofu stumptown aliqua, retro synth master cleanse. Mustache cliche tempor, williamsburg carles vegan helvetica. Reprehenderit butcher retro keffiyeh dreamcatcher synth. Cosby sweater eu banh mi, qui irure terry richardson ex squid. Aliquip placeat salvia cillum iphone. Seitan aliquip quis cardigan american apparel, butcher voluptate nisi qui.</p>
            </div>
            <div class=\"tab-pane fade\" id=\"dbus\">
              <p>Food truck fixie locavore, accusamus mcsweeney's marfa nulla single-origin coffee squid. Exercitation +1 labore velit, blog sartorial PBR leggings next level wes anderson artisan four loko farm-to-table craft beer twee. Qui photo booth letterpress, commodo enim craft beer mlkshk aliquip jean shorts ullamco ad vinyl cillum PBR. Homo nostrud organic, assumenda labore aesthetic magna delectus mollit. Keytar helvetica VHS salvia yr, vero magna velit sapiente labore stumptown. Vegan fanny pack odio cillum wes anderson 8-bit, sustainable jean shorts beard ut DIY ethical culpa terry richardson biodiesel. Art party scenester stumptown, tumblr butcher vero sint qui sapiente accusamus tattooed echo park.</p>
            </div>
            <div class=\"tab-pane fade\" id=\"ocaml\">
              <p>Etsy mixtape wayfarers, ethical wes anderson tofu before they sold out mcsweeney's organic lomo retro fanny pack lo-fi farm-to-table readymade. Messenger bag gentrify pitchfork tattooed craft beer, iphone skateboard locavore carles etsy salvia banksy hoodie helvetica. DIY synth PBR banksy irony. Leggings gentrify squid 8-bit cred pitchfork. Williamsburg banh mi whatever gluten-free, carles pitchfork biodiesel fixie etsy retro mlkshk vice blog. Scenester cred you probably haven't heard of them, vinyl craft beer blog stumptown. Pitchfork sustainable tofu synth chambray yr.</p>
            </div>
          </div>
";
	      p "inputs:";
	      of_args m.Method.inputs;
	      p "outputs:";
	      of_args m.Method.outputs;
	    ) i.Interface.methods;
	) x.Interfaces.interfaces;
      Xmlm.output output (`El_end);
      Buffer.contents buffer

let to_dbus_xml x =
  let open Xmlm in
      let buffer = Buffer.create 128 in
      let output = Xmlm.make_output ~nl:true ~indent:(Some 4) (`Buffer buffer) in
      Xmlm.output output (`Dtd None);
      Xmlm.output output (`El_start (("", "node"), [ ("", "name"), "/org/xen/xcp/" ^ x.Interfaces.name ]));
      Xmlm.output output (`El_start (("", "tp:docstring"), []));
      Xmlm.output output (`Data x.Interfaces.description);
      Xmlm.output output (`El_end);
      List.iter
	(fun i ->
	  Xmlm.output output (`El_start (("", "interface"), [ ("", "name"), "org.xen.xcp." ^ i.Interface.name ]));
      Xmlm.output output (`El_start (("", "tp:docstring"), []));
      Xmlm.output output (`Data i.Interface.description);
      Xmlm.output output (`El_end);
	  List.iter
	    (fun m ->
	      Xmlm.output output (`El_start (("", "method"), [ ("", "name"), m.Method.name ]));
	      Xmlm.output output (`El_start (("", "tp:docstring"), []));
	      Xmlm.output output (`Data m.Method.description);
	      Xmlm.output output (`El_end);
	      List.iter
		(fun arg ->
		  Xmlm.output output (`El_start (("", "arg"), [ ("", "type"), Type.string_of_t arg.Arg.ty; ("", "name"), arg.Arg.name; ("", "direction"), "in" ]));
	      Xmlm.output output (`El_start (("", "tp:docstring"), []));
	      Xmlm.output output (`Data arg.Arg.description);
	      Xmlm.output output (`El_end);
		  Xmlm.output output (`El_end);
		) m.Method.inputs;
	      List.iter
		(fun arg ->
		  Xmlm.output output (`El_start (("", "arg"), [ ("", "type"), Type.string_of_t arg.Arg.ty; ("", "name"), arg.Arg.name; ("", "direction"), "out" ]));
		  Xmlm.output output (`El_start (("", "tp:docstring"), []));
		  Xmlm.output output (`Data arg.Arg.description);
		  Xmlm.output output (`El_end);
		  Xmlm.output output (`El_end);
		) m.Method.outputs;
	      Xmlm.output output (`El_end);
	    ) i.Interface.methods;
	  Xmlm.output output (`El_end);
	) x.Interfaces.interfaces;
      Xmlm.output output (`El_end);

      Buffer.contents buffer


(* XXX: need documentation *)
let smapiv2 =
  let vdi_info =
    Type.(Struct(
      ( "vdi", Basic String ),
      [ "sr", Basic String;
	"content_id", Basic String;
	"name_label", Basic String;
	"name_description", Basic String;
	"ty", Basic String;
	"metadata_of_pool", Basic String;
	"is_a_snapshot", Basic Boolean;
	"snapshot_time", Basic String;
	"snapshot_of", Basic String;
	"read_only", Basic Boolean;
	"virtual_size", Basic Int64;
	"physical_utilisation", Basic Int64;
      ]
    )) in
  let sr = {
    Arg.name = "sr";
    ty = Type.(Basic String);
    description = "The Storage Repository to operate within";
  } in
  let vdi = {
    Arg.name = "vdi";
    ty = Type.(Basic String);
    description = "The Virtual Disk Image to operate on";
  } in
  let vdi_info' = {
    Arg.name = "vdi_info";
    ty = vdi_info;
    description = "The Virtual Disk Image properties";
  } in
  let params = {
    Arg.name = "params";
    ty = Type.(Dict(String, Basic String));
    description = "Additional key/value pairs";
  } in
  {
    Interfaces.name = "SMAPIv2";
    description = "The Storage Manager API";
    interfaces =
      [
	{
	  Interface.name = "VDI";
	  description = "Operations which operate on Virtual Disk Images";
	  methods = [
	    {
	      Method.name = "create";
	      description = "[create task sr vdi_info params] creates a new VDI in [sr] using [vdi_info]. Some fields in the [vdi_info] may be modified (e.g. rounded up), so the function returns the vdi_info which was used.";
	      inputs = [
		sr;
		vdi_info';
		params;
	      ];
	      outputs = [
		{ Arg.name = "new_vdi";
		  ty = vdi_info;
		  description = "The created Virtual Disk Image";
		}
	      ];
	    }; {
	      Method.name = "snapshot";
	      description = "[snapshot task sr vdi vdi_info params] creates a new VDI which is a snapshot of [vdi] in [sr]";
	      inputs = [
		sr;
		vdi;
		vdi_info';
		params;
	      ];
	      outputs = [
		{ Arg.name = "new_vdi";
		  ty = vdi_info;
		  description = "[snapshot task sr vdi vdi_info params] creates a new VDI which is a snapshot of [vdi] in [sr]";
		}
	      ];
	    }; {
	      Method.name = "clone";
	      description = "[clone task sr vdi vdi_info params] creates a new VDI which is a clone of [vdi] in [sr]";
	      inputs = [
		sr;
		vdi;
		vdi_info';
		params;
	      ];
	      outputs = [
		{ Arg.name = "new_vdi";
		  ty = vdi_info;
		  description = "[clone task sr vdi vdi_info params] creates a new VDI which is a clone of [vdi] in [sr]";
		}
	      ];
	    }; {
	      Method.name = "destroy";
	      description = "[destroy task sr vdi] removes [vdi] from [sr]";
	      inputs = [
		sr;
		vdi;
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "attach";
	      description = "[attach task dp sr vdi read_write] returns the [params] for a given [vdi] in [sr] which can be written to if (but not necessarily only if) [read_write] is true";
	      inputs = [
		{ Arg.name = "dp";
		  ty = Type.(Basic String);
		  description = "DataPath to attach this VDI for";
		};
		sr;
		vdi;
		{ Arg.name = "read_write";
		  ty = Type.(Basic Boolean);
		  description = "If true then the DataPath will be used read/write, false otherwise";
		}
	      ];
	      outputs = [
		{ Arg.name = "params";
		  ty = Type.(Basic String);
		  description = "xenstore backend params key";
		}
	      ];
	    }; {
	      Method.name = "activate";
	      description = "[activate task dp sr vdi] signals the desire to immediately use [vdi]. This client must have called [attach] on the [vdi] first.";
	      inputs = [
		{ Arg.name = "dp";
		  ty = Type.(Basic String);
		  description = "DataPath to attach this VDI for";
		};
		sr;
		vdi;
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "deactivate";
	      description = "[deactivate task dp sr vdi] signals that this client has stopped reading (and writing) [vdi].";
	      inputs = [
		{ Arg.name = "dp";
		  ty = Type.(Basic String);
		  description = "DataPath to deactivate";
		};
		sr;
		vdi;
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "detach";
	      description = "[detach task dp sr vdi] signals that this client no-longer needs the [params] to be valid.";
	      inputs = [
		{ Arg.name = "dp";
		  ty = Type.(Basic String);
		  description = "DataPath to detach";
		};
		sr;
		vdi;
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "copy";
	      description = "[copy task sr vdi url sr2] copies the data from [vdi] into a remote system [url]'s [sr2]";
	      inputs = [
		sr;
		vdi;
		{ Arg.name = "url";
		  ty = Type.(Basic String);
		  description = "URL which identifies a remote system";
		};
		{ sr with Arg.name = "dest" };
	      ];
	      outputs = [
		{ vdi with Arg.name = "new_vdi" }
	      ];
	    }; {
	      Method.name = "get_url";
	      description = "[get_url task sr vdi] returns a URL suitable for accessing disk data directly.";
	      inputs = [
		sr;
		vdi
	      ];
	      outputs = [
		{ Arg.name = "url";
		  ty = Type.(Basic String);
		  description = "URL which represents this VDI";
		}
	      ];
	    }; {
	      Method.name = "get_by_name";
	      description = "[get_by_name task sr name] returns the vdi within [sr] with [name]";
	      inputs = [
		sr;
		{ Arg.name = "name";
		  ty = Type.(Basic String);
		  description = "Name of the VDI to return";
		};
	      ];
	      outputs = [
		vdi
	      ];
	    }; {
	      Method.name = "set_content_id";
	      description = "[set_content_id task sr vdi content_id] tells the storage backend that a VDI has an updated [content_id]";
	      inputs = [
		sr;
		vdi;
		{ Arg.name = "content_id";
		  ty = Type.(Basic String);
		  description = "New value of the VDI content_id field";
		}
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "compose";
	      description = "[compose task sr vdi1 vdi2] layers the updates from [vdi2] onto [vdi1], modifying [vdi2]";
	      inputs = [
		sr;
		{ vdi with Arg.name = "vdi1" };
		{ vdi with Arg.name = "vdi2" };
	      ];
	      outputs = [
	      ];
	    }
	      
	  ]
	}; {
	  Interface.name = "SR";
	  description = "Operations which act on Storage Repositories";
	  methods = [
	    {
	      Method.name = "attach";
	      description = "[attach task sr]: attaches the SR";
	      inputs = [
		sr;
		{ Arg.name = "device_config";
		  ty = Type.(Dict(String, Basic String));
		  description = "Host-local SR configuration (e.g. address information)";
		};
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "detach";
	      description = "[detach task sr]: detaches the SR, first detaching and/or deactivating any active VDIs. This may fail with Sr_not_attached, or any error from VDI.detach or VDI.deactivate.";
	      inputs = [
		sr;
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "destroy";
	      description = "[destroy sr]: destroys (i.e. makes unattachable and unprobeable) the [sr], first detaching and/or deactivating any active VDIs. This may fail with Sr_not_attached, or any error from VDI.detach or VDI.deactivate.";
	      inputs = [
		sr;
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "reset";
	      description = "[reset task sr]: declares that the SR has been completely reset, e.g. by rebooting the VM hosting the SR backend.";
	      inputs = [
		sr;
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "scan";
	      description = "[scan task sr] returns a list of VDIs contained within an attached SR";
	      inputs = [
		sr;
	      ];
	      outputs = [
		(* XXX: vdi_info list *)
	      ];
	    }
	  ]
	}; {
	  Interface.name = "DP";
	  description = "Operations which act on DataPaths";
	  methods = [
	    {
	      Method.name = "create";
	      description = "[create task id]: creates and returns a dp";
	      inputs = [
		{ Arg.name = "id";
		  ty = Type.(Basic String);
		  description = "Human-readable DataPath name, for logging and diagnostics";
		}
	      ];
	      outputs = [
		{ Arg.name = "id";
		  ty = Type.(Basic String);
		  description = "Abstract DataPath identifier";
		}
	      ];
	    }; {
	      Method.name = "destroy";
	      description = "[destroy task id]: frees any resources associated with [id] and destroys it. This will typically do any needed VDI.detach, VDI.deactivate cleanup.";
	      inputs = [
		{ Arg.name = "id";
		  ty = Type.(Basic String);
		  description = "Abstract DataPath identifier";
		}; {
		  Arg.name = "allow_leak";
		  ty = Type.(Basic Boolean);
		  description = "If true then a failure will be logged but the call will not fail";
		}
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "diagnostics";
	      description = "[diagnostics ()]: returns a printable set of diagnostic information, typically including lists of all registered datapaths and their allocated resources.";
	      inputs = [
	      ];
	      outputs = [
		{ Arg.name = "diagnostics";
		  ty = Type.(Basic String);
		  description = "A string containing loggable human-readable diagnostics information";
		}
	      ];
	    }
	  ]
	}; {
	  Interface.name = "Mirror";
	  description = "Operations which act on disk mirrors.";
	  methods = [
	    {
	      Method.name = "start";
	      description = "[start task sr vdi url sr2] creates a VDI in remote [url]'s [sr2] and writes data synchronously. It returns the id of the VDI.";
	      inputs = [
		sr;
		vdi;
		{ Arg.name = "url";
		  ty = Type.(Basic String);
		  description = "The URL to mirror the VDI to";
		};
		{ sr with Arg.name = "dest" }
	      ];
	      outputs = [
		{ vdi with Arg.name = "new_vdi" }
	      ];	      
	    }; {
	      Method.name = "stop";
	      description = "[stop task sr vdi] stops mirroring local [vdi]";
	      inputs = [
		sr;
		vdi;
	      ];
	      outputs = [
	      ];	      
	    }
	  ]
	}
      ]
  }

let print_file = Unixext.file_lines_iter print_string

let _ =
(*
  print_string (to_dbus_xml smapiv2);
  print_string "";
  print_string "\n";
  print_string "";
  print_string (to_json smapiv2);
  print_string "\n";
  print_string "";
  to_rpclight smapiv2;
  print_string "";
*)
  print_file ("doc/header.html");
  print_string (to_html smapiv2);
  print_file ("doc/footer.html")

