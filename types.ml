
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

type arg = string * Type.t

module Method = struct
  type t = {
    name: string;
    inputs: arg list;
    outputs: arg list;
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
	    (fun (name, ty) ->
	      printf "@[%s@ :@ %s;@.@]" name (Type.ocaml_of_t ty) 
	    ) args;
	  printf "@.}@.@]" in
	of_args (m.Method.name ^ "_inputs") m.Method.inputs;
	of_args (m.Method.name ^ "_outputs") m.Method.outputs;
	printf "@[external %s: %s_inputs -> %s_outputs = \"\"@.@]" m.Method.name m.Method.name m.Method.name in
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
    `Assoc (List.map (fun (name, ty) -> name, `String (Type.string_of_t ty)) args) in
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
(*	      Xmlm.output output (`Data m.Method.description); *)
	      Xmlm.output output (`El_end);
	      List.iter
		(fun (name, ty) ->
		  Xmlm.output output (`El_start (("", "arg"), [ ("", "type"), Type.string_of_t ty; ("", "name"), name; ("", "direction"), "in" ]));
		  Xmlm.output output (`El_end);
		) m.Method.inputs;
	      List.iter
		(fun (name, ty) ->
		  Xmlm.output output (`El_start (("", "arg"), [ ("", "type"), Type.string_of_t ty; ("", "name"), name; ("", "direction"), "out" ]));
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
	      inputs = [
		"sr", Type.(Basic String);
		"vdi_info", vdi_info;
		"params", Type.(Dict(String, Basic String))
	      ];
	      outputs = [
		"new_vdi", vdi_info
	      ];
	    }; {
	      Method.name = "snapshot";
	      inputs = [
		"sr", Type.(Basic String);
		"vdi", Type.(Basic String);
		"vdi_info", vdi_info;
		"params", Type.(Dict(String, Basic String))
	      ];
	      outputs = [
		"new_vdi", vdi_info
	      ];
	    }; {
	      Method.name = "clone";
	      inputs = [
		"sr", Type.(Basic String);
		"vdi", Type.(Basic String);
		"vdi_info", vdi_info;
		"params", Type.(Dict(String, Basic String))
	      ];
	      outputs = [
		"new_vdi", vdi_info
	      ];
	    }; {
	      Method.name = "destroy";
	      inputs = [
		"sr", Type.(Basic String);
		"vdi", Type.(Basic String);
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "attach";
	      inputs = [
		"dp", Type.(Basic String);
		"sr", Type.(Basic String);
		"vdi", Type.(Basic String);
		"read_write", Type.(Basic Boolean);
	      ];
	      outputs = [
		"params", Type.(Basic String);
	      ];
	    }; {
	      Method.name = "activate";
	      inputs = [
		"dp", Type.(Basic String);
		"sr", Type.(Basic String);
		"vdi", Type.(Basic String);
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "deactivate";
	      inputs = [
		"dp", Type.(Basic String);
		"sr", Type.(Basic String);
		"vdi", Type.(Basic String);
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "deattach";
	      inputs = [
		"dp", Type.(Basic String);
		"sr", Type.(Basic String);
		"vdi", Type.(Basic String);
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "copy";
	      inputs = [
		"sr", Type.(Basic String);
		"vdi", Type.(Basic String);
		"url", Type.(Basic String);
		"dest", Type.(Basic String);
	      ];
	      outputs = [
		"new_vdi", Type.(Basic String);
	      ];
	    }; {
	      Method.name = "get_url";
	      inputs = [
		"sr", Type.(Basic String);
		"vdi", Type.(Basic String);
	      ];
	      outputs = [
		"url", Type.(Basic String);
	      ];
	    }; {
	      Method.name = "get_by_name";
	      inputs = [
		"sr", Type.(Basic String);
		"name", Type.(Basic String);
	      ];
	      outputs = [
		"vdi", Type.(Basic String);
	      ];
	    }; {
	      Method.name = "set_content_id";
	      inputs = [
		"sr", Type.(Basic String);
		"vdi", Type.(Basic String);
		"content_id", Type.(Basic String);
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "compose";
	      inputs = [
		"sr", Type.(Basic String);
		"vdi1", Type.(Basic String);
		"vdi2", Type.(Basic String);
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
	      inputs = [
		"sr", Type.(Basic String);
		"device_config", Type.(Dict(String, Basic String));
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "detach";
	      inputs = [
		"sr", Type.(Basic String);
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "destroy";
	      inputs = [
		"sr", Type.(Basic String);
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "reset";
	      inputs = [
		"sr", Type.(Basic String);
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "scan";
	      inputs = [
		"sr", Type.(Basic String);
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
	      inputs = [
		"id", Type.(Basic String);
	      ];
	      outputs = [
		"dp", Type.(Basic String);
	      ];
	    }; {
	      Method.name = "destroy";
	      inputs = [
		"id", Type.(Basic String);
		"allow_leak", Type.(Basic Boolean);
	      ];
	      outputs = [
	      ];
	    }; {
	      Method.name = "diagnostics";
	      inputs = [
	      ];
	      outputs = [
		"diagnostics", Type.(Basic String);
	      ];
	    }
	  ]
	}; {
	  Interface.name = "Mirror";
	  description = "Operations which act on disk mirrors.";
	  methods = [
	    {
	      Method.name = "start";
	      inputs = [
		"sr", Type.(Basic String);
		"vdi", Type.(Basic String);
		"url", Type.(Basic String);
		"dest", Type.(Basic String);
	      ];
	      outputs = [
		"new_vdi", Type.(Basic String);
	      ];	      
	    }; {
	      Method.name = "stop";
	      inputs = [
		"sr", Type.(Basic String);
		"vdi", Type.(Basic String);
	      ];
	      outputs = [
	      ];	      
	    }
	  ]
	}
      ]
  }

let _ =
  print_string (to_dbus_xml smapiv2);
  print_string "";
  print_string "\n";
  print_string "";
  print_string (to_json smapiv2);
  print_string "\n";
  print_string "";
  to_rpclight smapiv2
