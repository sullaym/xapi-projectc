open Lwt
open Lwt_io

let volumes_per_vm = 6
let networks_per_vm = 6

let debug_logging = ref false

let rec repeat f = function
  | 0 -> return ()
  | n ->
    lwt () = f n in
    repeat f (n-1)

let log fmt =
  Printf.kprintf
    (fun s ->
      if !debug_logging
      then Printf.fprintf Pervasives.stderr "%s\n%!" s
    ) fmt

let controller_start_multiple how_many =
  log "controller_start_multiple %ld" how_many;
  lwt bus = OBus_bus.session () in
  let vm = OBus_proxy.make (OBus_peer.make bus "org.xenserver.vm") ["org"; "xenserver"; "vm"] in
  let start = Unix.gettimeofday () in
  lwt () = repeat
    (fun i ->
      OBus_method.call Vm.Org_xenserver_api_vm.m_start vm (string_of_int i)
    ) (Int32.to_int how_many) in
  let time = Unix.gettimeofday () -. start in
  return (string_of_float time)

let controller_stop_multiple which =
  return "unknown"

let vm_start config =
  log "vm_start %s" config;
  (* Create a proxy for the remote object *)
  lwt bus = OBus_bus.session () in
  let volume = OBus_proxy.make (OBus_peer.make bus "org.xenserver.volume.example") ["org"; "xenserver"; "volume"; "example"] in
  let network = OBus_proxy.make (OBus_peer.make bus "org.xenserver.network") ["org"; "xenserver"; "network"] in
  lwt () = repeat
    (fun _ ->
      lwt (local_uri, id) = OBus_method.call Resource.Org_xenserver_api_resource.m_attach volume "iscsi://target/lun" in
      log "  got local_uri %s id %s" local_uri id;
      return ()
    ) volumes_per_vm in
  lwt () = repeat
    (fun _ ->
      lwt (local_uri, id) = OBus_method.call Resource.Org_xenserver_api_resource.m_attach network "sdn://magic/" in
      log "  got local_uri %s id %s" local_uri id;
      return ()
    ) networks_per_vm in
  return ()

let vm_stop id =
  log "vm_stop %s" id;
  return ()


let vm_interface =
 Vm.Org_xenserver_api_vm.(make {
   m_start = (fun obj config -> vm_start config);
   m_stop  = (fun obj id     -> vm_stop  id);
 })

let volume_attach global_uri =
  log "volume_attach %s" global_uri;
  return ("file://block/device", "some id")

let volume_detach id =
  log "volume_detach %s" id;
  return ()

let volume_interface =
 Resource.Org_xenserver_api_resource.(make {
   m_attach = (fun obj global_uri -> volume_attach global_uri);
   m_detach = (fun obj id         -> volume_detach id);
 })

let network_attach global_uri =
  log "network_attach %s" global_uri;
  return ("vlan://eth0/100", "some id")

let network_detach id =
  log "network_detach %s" id;
  return ()

let network_interface =
 Resource.Org_xenserver_api_resource.(make {
   m_attach = (fun obj global_uri -> network_attach global_uri);
   m_detach = (fun obj id         -> network_detach id);
 })

let controller_interface =
 Controller.Org_xenserver_api_controller.(make {
   m_start_multiple = (fun obj which -> controller_start_multiple which);
   m_stop_multiple  = (fun obj which -> controller_stop_multiple which);
 })

lwt () =
  let implement_vm = ref false in
  let implement_volume = ref false in
  let implement_network = ref false in
  let implement_control = ref false in
  let implement_all = ref false in
  Arg.parse [
    "-debug", Arg.Set debug_logging, "Print debug logging";
    "-vm",    Arg.Set implement_vm,  "Implement VM";
    "-volume",Arg.Set implement_volume, "Implement Volume";
    "-network", Arg.Set implement_network, "Implement Network";
    "-control", Arg.Set implement_control, "Implement Control";
    "-all",     Arg.Set implement_all,     "Implement everything";
  ] (fun x -> Printf.fprintf Pervasives.stderr "Ignoring argument: %s\n" x)
  "A simple system mockup";

  lwt bus = OBus_bus.session () in

  lwt () = if !implement_vm || !implement_all then begin
    lwt _ = OBus_bus.request_name bus "org.xenserver.vm" in
    let obj = OBus_object.make ~interfaces:[vm_interface] ["org"; "xenserver"; "vm"] in
    OBus_object.attach obj ();
    OBus_object.export bus obj;
    return ()
  end else return () in

  lwt () = if !implement_volume || !implement_all then begin
    lwt _ = OBus_bus.request_name bus "org.xenserver.volume" in
    let obj = OBus_object.make ~interfaces:[volume_interface] ["org"; "xenserver"; "volume"] in
    OBus_object.attach obj ();
    OBus_object.export bus obj;
    return ()
  end else return () in

  lwt () = if !implement_network || !implement_all then begin
    lwt _ = OBus_bus.request_name bus "org.xenserver.network" in
    let obj = OBus_object.make ~interfaces:[network_interface] ["org"; "xenserver"; "network"] in
    OBus_object.attach obj ();
    OBus_object.export bus obj;
    return ()
  end else return () in

  lwt () = if !implement_control || !implement_all then begin
    lwt _ = OBus_bus.request_name bus "org.xenserver.controller" in
    let obj = OBus_object.make ~interfaces:[controller_interface] ["org"; "xenserver"; "controller"] in
    OBus_object.attach obj ();
    OBus_object.export bus obj;
    return ()
  end else return () in

  (* Wait forever *)
  fst (wait ())
