open Rauc

type state = {
    mutable rauc_status: Rauc.status;
    mutable primary_slot: Slot.t option;
    mutable booted_slot: Slot.t;
}

let some_status : Rauc.Slot.status =
  {
    device = "Device";
    state = "Good";
    class' = "class";
    version = "0.0.0";
    installed_timestamp = "2023-01-01T00:00:00Z";
  }

class mock = object (self)
    val state : state = {
        rauc_status = { a = some_status; b = some_status };
        primary_slot = None;
        booted_slot = Slot.SystemA;
    }

    method set_status slot status =
      match slot with
      | Slot.SystemA -> state.rauc_status <- { state.rauc_status with a = status }
      | Slot.SystemB -> state.rauc_status <- { state.rauc_status with b = status }

    method get_status () = state.rauc_status |> Lwt.return

    method get_slot_status slot =
      match slot with
      | Slot.SystemA -> state.rauc_status.a
      | Slot.SystemB -> state.rauc_status.b

    method set_primary slot = state.primary_slot <- Some slot
    method get_primary () = state.primary_slot |> Lwt.return

    method set_booted_slot slot = state.booted_slot <- slot
    method get_booted_slot () = Lwt.return state.booted_slot

    method private extract_version bundle_path =
        let regex_str = {|.*-\([0-9]+\.[0-9]+\.[0-9]+.*\)\.raucb|} in
        let regex = Str.regexp regex_str in
        let m = Str.string_match regex bundle_path 0 in
        if m then
            Str.matched_group 1 bundle_path
        else
            Alcotest.fail @@
                "Failed to extract version from bundle_path: " ^ bundle_path

    method install (bundle_path : string) : unit Lwt.t =
        let vsn = self#extract_version bundle_path in
        let%lwt booted_slot = self#get_booted_slot () in
        let other_slot = match booted_slot with
            | Slot.SystemA -> Slot.SystemB
            | Slot.SystemB -> Slot.SystemA
        in
        (* "install" into non-booted slot *)
        let () = self#set_status other_slot {some_status with version = vsn} in
        let () = self#set_primary other_slot in
        (* TODO: what about mark_good? *)
        Lwt.return ()

    method mark_good _ = failwith "Not implemented"

    method to_module = (module struct
        let get_status = self#get_status
        let get_booted_slot = self#get_booted_slot
        let mark_good = self#mark_good
        let get_primary = self#get_primary
        let install = self#install
    end : Rauc_service.S)
end


