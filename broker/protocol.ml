open Cohttp
open Cohttp_lwt_unix
open Lwt


module Message = struct
	type t = {
		payload: string; (* switch to Rpc.t *)
		correlation_id: int;
		reply_to: string option;
	} with rpc

	let one_way payload = {
		payload = payload;
		correlation_id = 0;
		reply_to = None;
	}
end

module In = struct
	type t =
	| Login of string            (** Associate this transport-level channel with a session *)
	| Bind of string option      (** Listen on either an existing queue or a fresh one *)
	| Send of string * Message.t (** Send a message to a queue *)
	| Transfer of int64 * float  (** blocking wait for new messages *)
	| Ack of int64               (** ACK this particular message *)

	let rec split ?limit:(limit=(-1)) c s =
		let i = try String.index s c with Not_found -> -1 in
		let nlimit = if limit = -1 || limit = 0 then limit else limit - 1 in
		if i = -1 || nlimit = 0 then
			[ s ]
		else
			let a = String.sub s 0 i
			and b = String.sub s (i + 1) (String.length s - i - 1) in
			a :: (split ~limit: nlimit c b)

	let of_request req = match Request.meth req, split '/' (Request.path req) with
		| `GET, [ ""; "login"; token ] -> Some (Login token)
		| `GET, [ ""; "bind" ]         -> Some (Bind None)
		| `GET, [ ""; "bind"; name ]   -> Some (Bind (Some name))
		| `GET, [ ""; "ack"; id ]      -> Some (Ack (Int64.of_string id))
		| `GET, [ ""; "transfer"; ack_to; timeout ] ->
			Some (Transfer(Int64.of_string ack_to, float_of_string timeout))
		| `GET, [ ""; "send"; name; data ] ->
			let message = Message.one_way data in
			Some (Send (name, message))
		| _, _ -> None

	let to_request = function
		| Login token ->
			Request.make ~meth:`GET (Uri.make ~path:(Printf.sprintf "/login/%s" token) ())
		| Bind None ->
			Request.make ~meth:`GET (Uri.make ~path:"/bind" ())
		| Bind (Some name) ->
			Request.make ~meth:`GET (Uri.make ~path:(Printf.sprintf "/bind/%s" name) ())
		| Ack x ->
			Request.make ~meth:`GET (Uri.make ~path:(Printf.sprintf "/ack/%Ld" x) ())
		| Transfer(ack_to, timeout) ->
			Request.make ~meth:`GET (Uri.make ~path:(Printf.sprintf "/transfer/%Ld/%.16g" ack_to timeout) ())
		| Send (name, message) ->
			Request.make ~meth:`GET (Uri.make ~path:(Printf.sprintf "/send/%s/%s" name message.Message.payload) ())
end

module Out = struct
	type transfer = {
		messages: (int64 * Message.t) list;
	} with rpc

	type t =
	| Login
	| Bind of string
	| Send
	| Transfer of transfer
	| Ack

	let to_response = function
		| Login
		| Ack
		| Send -> Server.respond_string ~status:`OK ~body:"" ()
		| Bind name ->
			Server.respond_string ~status:`OK ~body:name ()
		| Transfer transfer ->
			Server.respond_string ~status:`OK ~body:(Jsonrpc.to_string (rpc_of_transfer transfer)) ()
end



module Connection = struct
	type t = Lwt_io.input Lwt_io.channel * Lwt_io.output Lwt_io.channel

	exception Failed_to_read_response

	exception Unsuccessful_response

	let rpc (ic, oc) frame =
		lwt () = Request.write (fun _ _ -> return ()) (In.to_request frame) oc in
		match_lwt Response.read ic with
		| Some response ->
			if Response.status response <> `OK then begin
				Printf.fprintf stderr "Failed to read response\n%!";
				lwt () = Response.write (fun _ _ -> return ()) response Lwt_io.stderr in
				fail Unsuccessful_response
			end else begin
				Printf.fprintf stderr "OK\n%!";
				match_lwt Response.read_body response ic with
				| Transfer.Final_chunk x -> return x
				| Transfer.Chunk x -> return x
				| Transfer.Done -> return ""
			end
		| None ->
			Printf.fprintf stderr "Failed to read response\n%!";
			fail Failed_to_read_response

	let make port token =
		let sockaddr = Lwt_unix.ADDR_INET(Unix.inet_addr_of_string "127.0.0.1", port) in
		let fd = Lwt_unix.socket Lwt_unix.PF_INET Lwt_unix.SOCK_STREAM 0 in
		lwt () = Lwt_unix.connect fd sockaddr in
		let ic = Lwt_io.of_fd ~close:(fun () -> Lwt_unix.close fd) ~mode:Lwt_io.input fd in
		let oc = Lwt_io.of_fd ~close:(fun () -> return ()) ~mode:Lwt_io.output fd in
		let c = ic, oc in
		lwt _ = rpc c (In.Login token) in
		return c

end
