open Protocol

let port = ref 8080
let name = ref "default_name"
let payload = ref "hello"
let reply = ref false

let main () =
	lwt c = Connection.make !port in


let _ =
	Arg.parse [
		"-port", Arg.Set_int port, (Printf.sprintf "port broker listens on (default %d)" !port);
		"-name", Arg.Set_string name, (Printf.sprintf "name to send message to (default %s)" !name);
		"-payload", Arg.Set_string payload, (Printf.sprintf "payload of message to send (default %s)" !payload);
		"-reply", Arg.Set reply, (Printf.sprintf "wait for a reply (default %b)" !reply);
	] (fun x -> Printf.fprintf stderr "Ignoring unexpected argument: %s" x)
		"Send a message to a name, optionally waiting for a response";

	Lwt_unix.run (make_server ()) 
