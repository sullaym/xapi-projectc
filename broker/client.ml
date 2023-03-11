open Cohttp_lwt_unix
open Lwt
open Protocol

let port = ref 8080
let name = ref "default_name"
let payload = ref "hello"
let reply = ref false


let main () =
	lwt c = Connection.make !port in
	lwt reply_to =
		if not !reply then return None
		else begin
			let frame = Frame.Bind None in
			let http_request = Frame.to_request frame in
			lwt queue_name = Connection.rpc c http_request in
			return (Some queue_name)
		end in
	let frame = Frame.Send(!name, { Message.payload = !payload; correlation_id = 0; reply_to }) in
	let http_request = Frame.to_request frame in
	lwt (_: string) = Connection.rpc c http_request in
	if not !reply then return ()
	else begin
		return ()

	end

let _ =
	Arg.parse [
		"-port", Arg.Set_int port, (Printf.sprintf "port broker listens on (default %d)" !port);
		"-name", Arg.Set_string name, (Printf.sprintf "name to send message to (default %s)" !name);
		"-payload", Arg.Set_string payload, (Printf.sprintf "payload of message to send (default %s)" !payload);
		"-reply", Arg.Set reply, (Printf.sprintf "wait for a reply (default %b)" !reply);
	] (fun x -> Printf.fprintf stderr "Ignoring unexpected argument: %s" x)
		"Send a message to a name, optionally waiting for a response";

	Lwt_unix.run (main ()) 
