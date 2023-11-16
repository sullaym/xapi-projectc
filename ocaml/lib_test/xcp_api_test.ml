(*
 * Copyright (C) Citrix Systems Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; version 2.1 only. with the special
 * exception on linking described in file LICENSE.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *)

open OUnit

let ( |> ) a b = b a
let id x = x

open Storage

module S = (SR_test(Lwt): SR with type 'a t = 'a Lwt.t)
module S_d = SR_server_dispatcher(S)
module SR = SR_client(S_d)


module V = (VDI_test(Lwt): VDI with type 'a t = 'a Lwt.t)
module V_d = VDI_server_dispatcher(V)
module VDI = VDI_client(V_d)

let base_path = "../../rpc-light/"

let readfile filename =
  let fd = Unix.openfile filename [ Unix.O_RDONLY ] 0o0 in
  let buffer = String.make (1024 * 1024) '\000' in
  let length = Unix.read fd buffer 0 (String.length buffer) in
  let () = Unix.close fd in
  String.sub buffer 0 length

let expect_ok = function
  | `Ok _ -> ()
  | `Error e -> raise e

let check_request_parser f relative_path =
  (base_path ^ relative_path) |> readfile |> Xmlrpc.call_of_string |> f |> expect_ok

let check_sr_request_parser = check_request_parser Storage.Types.SR.In.of_call

let sr_attach_request _ = check_sr_request_parser "sr.attach/request"
let sr_detach_request _ = check_sr_request_parser "sr.detach/request"
let sr_scan_request   _ = check_sr_request_parser "sr.scan/request"

let check_vdi_request_parser = check_request_parser Storage.Types.VDI.In.of_call

let vdi_activate_request   _ = check_vdi_request_parser "vdi.activate/request"
let vdi_attach_request     _ = check_vdi_request_parser "vdi.attach/request"
let vdi_clone_request      _ = check_vdi_request_parser "vdi.clone/request"
let vdi_create_request     _ = check_vdi_request_parser "vdi.create/request"
let vdi_deactivate_request _ = check_vdi_request_parser "vdi.deactivate/request"
let vdi_destroy_request    _ = check_vdi_request_parser "vdi.destroy/request"
let vdi_detach_request     _ = check_vdi_request_parser "vdi.detach/request"
let vdi_snapshot_request   _ = check_vdi_request_parser "vdi.snapshot/request"

let sr_attach_response _ =
  let xml = readfile (base_path ^ "sr.attach/response") in
  let resp = Xmlrpc.response_of_string xml in
  match Storage.result_of_response resp with
  | `Ok x -> let (_: Storage.Types.SR.Attach.Out.t) = Storage.Types.SR.Attach.Out.t_of_rpc x in ()
  | `Error e -> raise e

let sr_detach_response _ =
  let xml = readfile (base_path ^ "sr.detach/response") in
  let resp = Xmlrpc.response_of_string xml in
  match Storage.result_of_response resp with
  | `Ok x -> let (_: Storage.Types.SR.Detach.Out.t) = Storage.Types.SR.Detach.Out.t_of_rpc x in ()
  | `Error e -> raise e

let sr_detach_failure _ =
  let xml = readfile (base_path ^ "sr.detach/failure") in
  let resp = Xmlrpc.response_of_string xml in
  match Storage.result_of_response resp with
  | `Ok x -> failwith "unexpected success"
  | `Error (Storage.Backend_error(_, _)) -> ()
  | `Error e -> raise e

let exception_marshal_unmarshal e _ =
  let e = Storage.Backend_error("foo", ["a"; "b"]) in
  match Storage.result_of_response (Storage.response_of_exn e) with
  | `Error e' when e = e' -> ()
  | `Ok x -> failwith "unexpected success"
  | `Error e -> raise e

let exception_marshal_unmarshal1 = exception_marshal_unmarshal (Storage.Cancelled "bad luck")
let exception_marshal_unmarshal2 = exception_marshal_unmarshal (Storage.Backend_error("foo", ["a"; "b"]))

let _ =
  let verbose = ref false in
  Arg.parse [
    "-verbose", Arg.Unit (fun _ -> verbose := true), "Run in verbose mode";
  ] (fun x -> Printf.fprintf stderr "Ignoring argument: %s" x)
    "Test xcp-api protocol code";

  let suite = "xen-api" >:::
              [
                "sr_attach_request" >:: sr_attach_request;
                "sr_attach_response" >:: sr_attach_response;
                "sr_detach_request" >:: sr_detach_request;
                "sr_detach_response" >:: sr_detach_request;
                "sr_detach_failure" >:: sr_detach_failure;
                "exception_marshal_unmarshal1" >:: exception_marshal_unmarshal1;
                "exception_marshal_unmarshal2" >:: exception_marshal_unmarshal2;
                "sr_scan_request" >:: sr_scan_request;
                "vdi_attach_request" >:: vdi_attach_request;
                (*
                "vdi_activate_request" >:: vdi_activate_request;
                *)
                "vdi_clone_request" >:: vdi_clone_request;
                "vdi_create_request" >:: vdi_create_request;
                (*
                "vdi_deactivate_request" >:: vdi_deactivate_request;
                *)
                "vdi_destroy_request" >:: vdi_destroy_request;
                (*
                "vdi_detach_request" >:: vdi_detach_request;
                *)
                "vdi_snapshot_request" >:: vdi_snapshot_request;
              ] in
  run_test_tt ~verbose:!verbose suite
