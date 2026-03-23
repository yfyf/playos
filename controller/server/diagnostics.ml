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
} [@@deriving protocol ~driver:(module Jsonm)]

type interface_dict = (string * interface_info) list [@@deriving protocol ~driver:(module Jsonm)]

let interface_dict_to_jsonm (dict : interface_dict) =
  `O (List.map (fun (k, v) -> (k, interface_info_to_jsonm v)) dict)

let interface_dict_of_jsonm = function
  | `O items ->
      List.map (fun (k, v) -> (k, interface_info_of_jsonm v)) items
  | _ -> failwith "Expected a JSON object"

type diagnostics_res = {
  wifi : interface_dict;
  ethernet : interface_dict;
  driver : string;
} [@@deriving protocol ~driver:(module Jsonm)]

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

let get_iface_info iface =
  let%lwt stats = get_stats iface in
  let%lwt status = get_status iface in
  Lwt.return (iface, { status; stats })

let getInfo () =
  let%lwt wifi_ifaces = get_ifaces "w" in
  let%lwt eth_ifaces = get_ifaces "e" in

  let%lwt wifi = Lwt_list.map_s get_iface_info wifi_ifaces in
  let%lwt ethernet = Lwt_list.map_s get_iface_info eth_ifaces in

  let%lwt driver = run_cmd "systemctl show -p ActiveState --value dividat-driver" in
  let driver = if driver = "" then "unknown" else driver in

  Lwt.return { wifi; ethernet; driver }

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

let build app =
  app
  (* Attach our new global middleware *)
  |> middleware cors_middleware

  |> get "/diagnostics" (fun _ ->
         let%lwt server_info = getInfo () in
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
