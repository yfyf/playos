open Connman.Service
open Tyxml.Html
open Protocol_conv_jsonm

let service_item interface_annotations ({ id; name; strength; ipv4 } as service)
    =
  let icon =
    match strength with
    | Some s ->
        Icon.wifi ~strength:s ()
    | None ->
        Icon.ethernet
  in
  let classes =
    [ "d-NetworkList__Network" ]
    @
    if Connman.Service.is_connected service then
      [ "d-NetworkList__Network--Connected" ]
    else []
  in
  li
    [ a
        ~a:[ a_class classes; a_href ("/network/" ^ id) ]
        [ div
            [ txt name
            ; span
                ~a:[ a_class [ "d-NetworkList__Labels" ] ]
                (List.assoc_opt service.ethernet.interface interface_annotations
                |> Option.value ~default:[]
                |> List.map (fun label_text ->
                    span
                      ~a:[ a_class [ "d-NetworkList__Label" ] ]
                      [ txt label_text ]
                )
                )
            ]
        ; ( match ipv4 with
          | Some ipv4_addr ->
              div
                ~a:[ a_class [ "d-NetworkList__Address" ] ]
                [ txt ipv4_addr.address ]
          | None ->
              space ()
          )
        ; div ~a:[ a_class [ "d-NetworkList__Icon" ] ] [ icon ]
        ; div ~a:[ a_class [ "d-NetworkList__Chevron" ] ] [ txt "ᐳ" ]
        ]
    ]

type params =
  { proxy : string option
  ; services : Connman.Service.t list
  ; interfaces : Network.Interface.t list
  ; interface_annotations : (string * string list) list
  }
[@@deriving protocol ~driver:(module Jsonm)]

(* Helper to filter, enumerate, and format MAC addresses *)
let render_macs label_prefix predicate interfaces =
    let items = List.filter predicate interfaces in
    let count = List.length items in
    List.mapi (fun index (i : Network.Interface.t) ->
      let label =
        if count > 1 then Printf.sprintf "%s MAC %d" label_prefix (index + 1)
        else label_prefix ^ " MAC"
      in
      span
        ~a:[ a_class [ "d-Title__Meta" ]
           ]
        [ txt (Printf.sprintf "%s: " label)
        ; span ~a:[ a_style "text-transform: uppercase" ] [ txt i.address ]
        ]
    ) items

let html { proxy; services; interfaces; interface_annotations } =
  let connected_services, available_services =
    List.partition Connman.Service.is_connected services
  in
  let mac_addresses =
    render_macs "Ethernet" Network.Interface.is_ethernet interfaces
    @ render_macs "Wi-Fi" Network.Interface.is_wifi interfaces
  in
  Page.html ~current_page:Page.Network
    ~header:
      (Page.header_title ~icon:Icon.world
         ~right_action:
           (a ~a:[ a_href "/network"; a_class [ "d-Button" ] ] [ txt "Refresh" ])
      [span ([ txt "Network" ]
           @ 
           (if mac_addresses = [] then [] 
            else 
              [ br ()
              ; small
                  ~a:[ a_style "font-size: 0.6rem; color: #666; font-weight: normal; display: block; line-height:1; display: flex; flex-direction: row; gap: 0.75rem;" ]
                  mac_addresses
              ]
           )
         )
      ]
      )
    (div
       [ ( if List.length connected_services = 0 then txt ""
           else
             section
               [ ul
                   ~a:[ a_class [ "d-NetworkList" ]; a_role [ "list" ] ]
                   (List.map
                      (service_item interface_annotations)
                      connected_services
                   )
               ]
         )
       ; Definition.list
           (( match proxy with
              | Some p ->
                  [ Definition.term [ txt "Proxy" ]
                  ; Definition.description [ txt p ]
                  ]
              | None ->
                  []
              )
           @ [ Definition.term [ txt "Internet" ]
             ; Definition.description
                 [ div
                     ~a:
                       [ a_class [ "d-Spinner" ]
                       ; Unsafe.string_attrib "is" "internet-status"
                       ]
                     []
                 ]
             ]
           )
       ; section
           [ h2 ~a:[ a_class [ "d-Title" ] ] [ txt "Available Networks" ]
           ; ( if List.length available_services = 0 then
                 p
                   ~a:[ a_class [ "d-Paragraph" ] ]
                   [ txt "No networks available" ]
               else
                 ul
                   ~a:[ a_class [ "d-NetworkList" ]; a_role [ "list" ] ]
                   (List.map (service_item []) available_services)
             )
           ]
       ; section
           [ h2 ~a:[ a_class [ "d-Title" ] ] [ txt "Network Interfaces" ]
           ; div
               ~a:[ a_class [ "d-Preformatted" ]; a_style "display:flex;flex-direction: column;" ]
               (render_macs "Ethernet" Network.Interface.is_ethernet interfaces @ render_macs "Wi-Fi" Network.Interface.is_wifi interfaces )
           ]
       ]
    )
