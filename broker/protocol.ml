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

module Frame = struct
	type t =
	| Send of string * Message.t
	| Transfer of string (* ack to *)
	| Connect
	| Bind of string

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
		| `GET, [ ""; "bind"; name ] -> Some (Bind name)
		| `GET, [ ""; "connection" ] -> Some Connect
		| `GET, [ ""; "transfer"; ack_to ] -> Some (Transfer ack_to)
		| `GET, [ ""; "send"; name; data ] ->
			let message = Message.one_way data in
			Some (Send (name, message))
		| _, _ -> None

	let to_request = function
		| Bind name ->
			Request.make ~meth:`GET (Uri.make ~path:(Printf.sprintf "/bind/%s" name) ())
		| Connect ->
			Request.make ~meth:`GET (Uri.make ~path:"/connection" ())
		| Transfer ack_to ->
			Request.make ~meth:`GET (Uri.make ~path:(Printf.sprintf "/transfer/%s" ack_to) ())
		| Send (name, message) ->
			Request.make ~meth:`GET (Uri.make ~path:(Printf.sprintf "/send/%s/%s" name message.Message.payload) ())
end




module Connection = struct
	type t = Lwt_io.input Lwt_io.channel * Lwt_io.output Lwt_io.channel

	let make port =
		let sockaddr = Lwt_unix.ADDR_INET(Unix.inet_addr_of_string "127.0.0.1", port) in
		let fd = Lwt_unix.socket Lwt_unix.PF_INET Lwt_unix.SOCK_STREAM 0 in
		lwt () = Lwt_unix.connect fd sockaddr in
		let ic = Lwt_io.of_fd ~close:(fun () -> Lwt_unix.close fd) ~mode:Lwt_io.input fd in
		let oc = Lwt_io.of_fd ~close:(fun () -> return ()) ~mode:Lwt_io.output fd in
		return (ic, oc)

	let rpc (ic, oc) request =
		lwt () = Request.write (fun _ _ -> return ()) request oc in
		match_lwt Response.read ic with
		| Some response ->
			if Response.status response <> `OK then begin
				Printf.fprintf stderr "Failed to read response\n%!";
				lwt () = Response.write (fun _ _ -> return ()) response Lwt_io.stderr in
				return ()
			end else begin
				Printf.fprintf stderr "OK\n%!";
				return ()
			end
		| None ->
			Printf.fprintf stderr "Failed to read response\n%!";
			return ()

end
