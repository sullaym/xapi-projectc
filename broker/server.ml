open Cohttp_lwt_unix
open Lwt
open Protocol

let port = ref 8080
let name = ref "server"

module Server = struct

	let listen process port name =
		let token = Printf.sprintf "%d" (Unix.getpid ()) in
		lwt c = Connection.make port token in

		lwt (_: string) = Connection.rpc c (In.Create (Some name)) in
		lwt (_: string) = Connection.rpc c (In.Subscribe name) in
		Printf.fprintf stdout "Serving requests forever\n%!";

		let rec loop from =
			let timeout = 5. in
			let frame = In.Transfer(from, timeout) in
			lwt raw = Connection.rpc c frame in
			let transfer = Out.transfer_of_rpc (Jsonrpc.of_string raw) in
			match transfer.Out.messages with
			| [] -> loop from
			| m :: ms ->
				lwt () = Lwt_list.iter_s
					(fun (i, m) ->
						lwt response = process m.Message.payload in
						lwt () =
							match m.Message.reply_to with
							| None ->
								Printf.fprintf stderr "No reply_to\n%!";
								return ()
							| Some reply_to ->
								Printf.fprintf stderr "Sending reply to %s\n%!" reply_to;
								let request = In.Send(reply_to, { m with Message.reply_to = None; payload = response }) in
								lwt (_: string) = Connection.rpc c request in
								return () in
						let request = In.Ack i in
						lwt (_: string) = Connection.rpc c request in
						return ()
					) transfer.Out.messages in
				let from = List.fold_left max (fst m) (List.map fst ms) in
				loop from in
		loop (-1L)

end

let process x = return x

let main () =
	Server.listen process !port !name

let _ =
	Arg.parse [
		"-port", Arg.Set_int port, (Printf.sprintf "port broker listens on (default %d)" !port);
		"-name", Arg.Set_string name, (Printf.sprintf "name to send message to (default %s)" !name);
	] (fun x -> Printf.fprintf stderr "Ignoring unexpected argument: %s" x)
		"Respond to RPCs on a name";

	Lwt_unix.run (main ()) 
