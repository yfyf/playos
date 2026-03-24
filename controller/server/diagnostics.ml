open Protocol_conv_jsonm
open Opium_kernel.Rock
open Opium.App

(* --- Types for the GET /diagnostics JSON response --- *)

type network_stats = {
  rx_packets : int;
  tx_packets : int;
  rx_bytes : int;
  tx_bytes : int;
} [@@deriving protocol ~driver:(module Jsonm)]

type interface_info = {
  status : string;
  stats : network_stats;
  annotations : string list;
  ping_rate : float option;
} [@@deriving protocol ~driver:(module Jsonm)]

type interface_dict = (string * interface_info) list [@@deriving protocol ~driver:(module Jsonm)]

let interface_dict_to_jsonm (dict : interface_dict) =
  `O (List.map (fun (k, v) -> (k, interface_info_to_jsonm v)) dict)

let interface_dict_of_jsonm _ =
  failwith "Expected a JSON object"

type interface_annotations = (string * string list) list

(* --- USB stats types --- *)

type usb_device_stats = {
  in_bytes : int;
  out_bytes : int;
} [@@deriving protocol ~driver:(module Jsonm)]

type usb_dict = (string * usb_device_stats) list [@@deriving protocol ~driver:(module Jsonm)]

let usb_dict_to_jsonm (dict : usb_dict) =
  `O (List.map (fun (k, v) -> (k, usb_device_stats_to_jsonm v)) dict)

let usb_dict_of_jsonm _ =
  failwith "Expected a JSON object"

type diagnostics_res = {
  wifi : interface_dict;
  ethernet : interface_dict;
  driver : string;
  rfid : string;
  usb : usb_dict;
} [@@deriving protocol ~driver:(module Jsonm)]

(* --- Ping generate request type --- *)

type ping_generate_req = {
  interface : string;
  rate : float option;
} [@@deriving protocol ~driver:(module Jsonm)]

(* --- Global state for ping processes --- *)

let ping_processes : (string, Lwt_process.process_none * float) Hashtbl.t = Hashtbl.create 16

(* --- Global state for USB traffic monitoring --- *)

(* Key is "bus_id.device_address", value is (in_bytes, out_bytes) *)
let usb_stats_table : (string, int * int) Hashtbl.t = Hashtbl.create 16
let usb_monitor_started = ref false

let start_usb_monitor () =
  if not !usb_monitor_started then begin
    usb_monitor_started := true;
    let cmd = ("tshark", [|
      "tshark"; "-i"; "usbmon0";
      "-Y"; "usb.urb_len > 0 and usb.urb_type == URB_COMPLETE";
      "-T"; "fields";
      "-e"; "usb.bus_id";
      "-e"; "usb.device_address";
      "-e"; "usb.endpoint_address.direction";
      "-e"; "usb.urb_len";
      "-E"; "separator=,"
    |]) in
    let proc = Lwt_process.open_process_in ~stderr:`Dev_null cmd in
    let rec read_loop () =
      Lwt.catch
        (fun () ->
          match%lwt Lwt_io.read_line_opt proc#stdout with
          | None -> Lwt.return_unit
          | Some line ->
              (* Parse CSV: bus_id,device_address,direction,urb_len *)
              (match String.split_on_char ',' line with
               | [bus_id; device_addr; direction; urb_len] ->
                   let key = "bus" ^ bus_id ^ ".dev" ^ device_addr in
                   let len = int_of_string_opt urb_len |> Option.value ~default:0 in
                   let (in_bytes, out_bytes) =
                     match Hashtbl.find_opt usb_stats_table key with
                     | Some (i, o) -> (i, o)
                     | None -> (0, 0)
                   in
                   (* direction "1" = IN (device to host), "0" = OUT (host to device) *)
                   let (new_in, new_out) =
                     if direction = "1" then (in_bytes + len, out_bytes)
                     else (in_bytes, out_bytes + len)
                   in
                   Hashtbl.replace usb_stats_table key (new_in, new_out)
               | _ -> ());
              read_loop ())
        (fun _ -> Lwt.return_unit)
    in
    Lwt.async read_loop
  end

let get_usb_stats () =
  Hashtbl.fold (fun key (in_bytes, out_bytes) acc ->
    (key, { in_bytes; out_bytes }) :: acc
  ) usb_stats_table []

let kill_ping_process iface =
  match Hashtbl.find_opt ping_processes iface with
  | Some (proc, _) ->
      Hashtbl.remove ping_processes iface;
      proc#kill Sys.sigterm;
      let%lwt _ = proc#status in
      Lwt.return_unit
  | None -> Lwt.return_unit

let start_ping_process iface rate =
  let%lwt () = kill_ping_process iface in
  if rate > 0.0 then begin
    let interval = Printf.sprintf "%f" (1.0 /. rate) in
    let proc = Lwt_process.open_process_none ~stdout:`Dev_null ~stderr:`Dev_null
      ("ping", [| "ping"; "-I"; iface; "-f"; "-i"; interval; "-b"; "255.255.255.255" |]) in
    Hashtbl.replace ping_processes iface (proc, rate);
    (* Monitor process and clean up when it dies *)
    Lwt.async (fun () ->
      let%lwt _ = proc#status in
      (* Only remove if the entry still refers to this process *)
      (match Hashtbl.find_opt ping_processes iface with
       | Some (p, _) when p == proc -> Hashtbl.remove ping_processes iface
       | _ -> ());
      Lwt.return_unit);
    Lwt.return_unit
  end else
    Lwt.return_unit

let get_ping_rate iface =
  match Hashtbl.find_opt ping_processes iface with
  | Some (_, rate) -> Some rate
  | None -> None

(* --- Helper functions for Linux system commands --- *)

let run_cmd cmd =
  Lwt.catch
    (fun () ->
       let%lwt out = Lwt_process.pread (Lwt_process.shell cmd) in
       Lwt.return (String.trim out))
    (fun _ -> Lwt.return "")

let run_cmd_lines cmd =
  let%lwt out = run_cmd cmd in
  let lines = String.split_on_char '\n' out in
  Lwt.return (List.filter (fun s -> s <> "") lines)

let run_cmd_ignore cmd =
  Lwt.catch
    (fun () ->
       let%lwt _ = Lwt_process.exec (Lwt_process.shell cmd) in
       Lwt.return_unit)
    (fun _ -> Lwt.return_unit)

let read_sys_int path =
  let%lwt content = run_cmd (Printf.sprintf "cat %s 2>/dev/null" path) in
  match int_of_string_opt content with
  | Some v -> Lwt.return v
  | None -> Lwt.return 0

(* --- Network information gatherers --- *)

let get_ifaces prefix =
  run_cmd_lines (Printf.sprintf "ls /sys/class/net | grep '^%s'" prefix)

let get_stats iface =
  let base_path = "/sys/class/net/" ^ iface ^ "/statistics/" in
  let%lwt rx_packets = read_sys_int (base_path ^ "rx_packets") in
  let%lwt tx_packets = read_sys_int (base_path ^ "tx_packets") in
  let%lwt rx_bytes = read_sys_int (base_path ^ "rx_bytes") in
  let%lwt tx_bytes = read_sys_int (base_path ^ "tx_bytes") in
  Lwt.return { rx_packets; tx_packets; rx_bytes; tx_bytes }

let get_status iface =
  let%lwt state = run_cmd (Printf.sprintf "cat /sys/class/net/%s/operstate 2>/dev/null" iface) in
  if state = "" then Lwt.return "unknown" else Lwt.return state

let get_iface_info annotations iface =
  let%lwt stats = get_stats iface in
  let%lwt status = get_status iface in
  let iface_annotations =
    match List.assoc_opt iface annotations with
    | Some a -> a
    | None -> []
  in
  let ping_rate = get_ping_rate iface in
  Lwt.return (iface, { status; stats; annotations = iface_annotations; ping_rate })

let getInfo annotations =
  let%lwt wifi_ifaces = get_ifaces "w" in
  let%lwt eth_ifaces = get_ifaces "e" in

  let%lwt wifi = Lwt_list.map_s (get_iface_info annotations) wifi_ifaces in
  let%lwt ethernet = Lwt_list.map_s (get_iface_info annotations) eth_ifaces in

  let%lwt driver = run_cmd "systemctl show -p ActiveState --value dividat-driver" in
  let driver = if driver = "" then "unknown" else driver in

  let%lwt rfid = run_cmd "systemctl show -p ActiveState --value pcscd.socket" in
  let rfid = if rfid = "" then "unknown" else rfid in

  let usb = get_usb_stats () in

  Lwt.return { wifi; ethernet; driver; rfid; usb }

(* --- Global CORS Middleware --- *)

let cors_headers = [
  ("Access-Control-Allow-Origin", "*");
  ("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  ("Access-Control-Allow-Headers", "Content-Type");
]

let cors_middleware =
  let filter handler req =
    (* Look inside the wrapped Cohttp request to get the method *)
    match req.Request.request.meth with
    | `OPTIONS ->
        (* Immediately answer preflight requests without hitting your routes *)
        let headers = Cohttp.Header.of_list cors_headers in
        Lwt.return (Response.of_string_body "" ~headers)
    | _ ->
        (* For all other requests, let the normal route handler run, then append headers *)
        let%lwt res = handler req in
        let headers = Cohttp.Header.add_list res.Response.headers cors_headers in
        Lwt.return { res with Response.headers = headers }
  in
  Middleware.create ~name:"Global CORS" ~filter

(* --- HTTP response helpers --- *)

(* We removed the manual CORS injection here since the middleware handles it *)
let resp_json ?code json =
  let headers = Cohttp.Header.init_with "content-type" "application/json" in
  Ezjsonm.value_to_string json |> Response.of_string_body ?code ~headers

let respond_ok () =
  Lwt.return (resp_json (Ezjsonm.dict [("status", Ezjsonm.string "ok")]))

(* --- App Builder --- *)

let build ~get_interface_annotations app =
  (* Start USB traffic monitoring *)
  start_usb_monitor ();

  app
  (* Attach our new global middleware *)
  |> middleware cors_middleware

  |> get "/diagnostics" (fun _ ->
         let%lwt interface_annotations = get_interface_annotations () in
         let%lwt server_info = getInfo interface_annotations in
         Lwt.return (resp_json (diagnostics_res_to_jsonm server_info)))

  |> post "/diagnostics/wifi/on" (fun _ ->
         let%lwt _ = run_cmd_ignore "rfkill unblock wifi && for i in $(ls /sys/class/net | grep '^w'); do ip link set $i up; done" in
         respond_ok ())
  |> post "/diagnostics/wifi/off" (fun _ ->
         let%lwt _ = run_cmd_ignore "rfkill block wifi && for i in $(ls /sys/class/net | grep '^w'); do ip link set $i down; done" in
         respond_ok ())

  |> post "/diagnostics/eth/on" (fun _ ->
         let%lwt _ = run_cmd_ignore "for i in $(ls /sys/class/net | grep '^e'); do ip link set $i up; done" in
         respond_ok ())
  |> post "/diagnostics/eth/off" (fun _ ->
         let%lwt _ = run_cmd_ignore "for i in $(ls /sys/class/net | grep '^e'); do ip link set $i down; done" in
         respond_ok ())

  |> post "/diagnostics/driver/on" (fun _ ->
         let%lwt _ = run_cmd_ignore "systemctl start dividat-driver" in
         respond_ok ())
  |> post "/diagnostics/driver/off" (fun _ ->
         let%lwt _ = run_cmd_ignore "systemctl stop dividat-driver" in
         respond_ok ())

  |> post "/diagnostics/rfid/on" (fun _ ->
         let%lwt _ = run_cmd_ignore "systemctl start pcscd.socket pcscd.service" in
         respond_ok ())
  |> post "/diagnostics/rfid/off" (fun _ ->
         let%lwt _ = run_cmd_ignore "systemctl stop pcscd.service pcscd.socket" in
         respond_ok ())

  |> post "/diagnostics/ping/generate" (fun req ->
         let%lwt body_str = Cohttp_lwt.Body.to_string req.Request.body in
         match Ezjsonm.value_from_string body_str with
         | `O _ as json ->
             (match ping_generate_req_of_jsonm json with
              | Ok req_data ->
                  let rate = Option.value req_data.rate ~default:0.0 in
                  let%lwt () = start_ping_process req_data.interface rate in
                  respond_ok ()
              | Error _ ->
                  Lwt.return (resp_json ~code:(`Code 400) (Ezjsonm.dict [("error", Ezjsonm.string "Invalid request")])))
         | _ ->
             Lwt.return (resp_json ~code:(`Code 400) (Ezjsonm.dict [("error", Ezjsonm.string "Expected JSON object")]))
         | exception _ ->
             Lwt.return (resp_json ~code:(`Code 400) (Ezjsonm.dict [("error", Ezjsonm.string "Invalid JSON")])))
