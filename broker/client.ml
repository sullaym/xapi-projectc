open Cohttp_lwt_unix
open Lwt
open Protocol

let port = ref 8080
let name = ref "default_name"
let payload = ref "hello"
let reply = ref false

(* New semantics:

   TCP connect
   Login "constant"
                       TCP connect
                       Login "constant"
   <-- both connections are associated with the same session
   <-- session will be GCed when the connections are dropped

   Bind "name"
   Send(foo, reply_to "name")
                       Transfer


   So the switch has

   Connection* -> Session -> Binding*
*)

let fresh_correlation_id =
	let counter = ref 0 in
	fun () ->
		let result = !counter in
		incr counter;
		result

let main () =
	let token = Printf.sprintf "%d" (Unix.getuid ()) in
	lwt requests_conn = Connection.make !port token
	and events_conn = Connection.make !port token in
 
	let wakener = Hashtbl.create 10 in
	let (_ : unit Lwt.t) =
		let rec loop ack_to =
			let timeout = 5. in
			let frame = Frame.Transfer(ack_to, timeout) in
			lwt _ = Connection.rpc events_conn frame in
			(* XXX: read responses *)
			loop ack_to in
		loop "" in

	lwt reply_to =
		if not !reply then return None
		else begin
			let frame = Frame.Bind None in
			lwt queue_name = Connection.rpc requests_conn frame in
			return (Some queue_name)
		end in
	let correlation_id = fresh_correlation_id () in
	let frame = Frame.Send(!name, { Message.payload = !payload; correlation_id; reply_to }) in
	lwt (_: string) = Connection.rpc requests_conn frame in
	if not !reply then return ()
	else begin
		Printf.fprintf stderr "waiting for response\n%!";
		let t, u = Lwt.task () in
		Hashtbl.add wakener correlation_id u;
		lwt response = t in
		Printf.fprintf stdout "%s\n%!" response.Message.payload;
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
