open! Import
open Std_internal
(* The code here refers to c functions that are not part of the library.  Instead, at link
   time of exe, bc, and toplevels, we include an object file that implements the given
   functions.  That way, we can update the functions to include the latest version info
   without having to recompile this library and everything that depends on it. *)
external generated_build_info : unit -> string = "generated_build_info"
external generated_hg_version : unit -> string = "generated_hg_version"

let trim_trailing_newline s =
  match (String.chop_suffix s ~suffix:"\n") with
  | Some s -> s
  | None -> s

let build_info = generated_build_info ()
let hg_version = trim_trailing_newline (generated_hg_version ())

let version = String.tr ~target:'\n' ~replacement:' ' hg_version
let version_list = String.split ~on:'\n' hg_version

let arg_spec = [
  ("-version",
   Arg.Unit
     (fun () ->
        print_endline hg_version;
        exit 0),
   " Print the hg revision of this build and exit");
  ("-build_info",
   Arg.Unit
     (fun () ->
        print_endline build_info;
        exit 0),
   " Print build info as sexp and exit");
]

module Application_specific_fields = struct
  type t = Sexp.t String.Map.t [@@deriving sexp]
end

module Time_float_with_limited_parsing = struct
  type t = Time_float.t * Sexp.t
  let t_of_sexp sexp =
    let str = string_of_sexp sexp in
    try
      match String.chop_suffix str ~suffix:"Z" with
      | None -> failwith "zone must be Z"
      | Some rest ->
        match String.lsplit2 rest ~on:' ' with
        | None -> failwith "time must contain one space between date and ofday"
        | Some (date, ofday) ->
          let date = Date.t_of_sexp (sexp_of_string date) in
          let ofday = Time_float.Ofday.t_of_sexp (sexp_of_string ofday) in
          Time_float.of_date_ofday date ofday ~zone:Time_float.Zone.utc, sexp
    with
    | Sexplib.Conv.Of_sexp_error (e, _) | e -> raise (Sexplib.Conv.Of_sexp_error (e, sexp))

  let sexp_of_t_ref = ref (fun (_, sexp) -> sexp)
  let sexp_of_t time = !sexp_of_t_ref time
end

type t = {
  username                    : string sexp_option;
  hostname                    : string sexp_option;
  kernel                      : string sexp_option;
  build_time                  : Time_float_with_limited_parsing.t sexp_option;
  x_library_inlining          : bool;
  portable_int63              : bool;
  dynlinkable_code            : bool;
  ocaml_version               : string;
  executable_path             : string;
  build_system                : string;
  application_specific_fields : Application_specific_fields.t sexp_option;
} [@@deriving sexp]

let build_info_as_sexp =
  Exn.handle_uncaught_and_exit (fun () -> Sexp.of_string build_info)
;;

let t = Exn.handle_uncaught_and_exit (fun () -> t_of_sexp build_info_as_sexp)

let { username;
      hostname;
      kernel;
      build_time = build_time_and_sexp;
      x_library_inlining;
      portable_int63;
      dynlinkable_code;
      ocaml_version;
      executable_path;
      build_system;
      application_specific_fields;
    } = t
;;

let build_time =
  match build_time_and_sexp with
  | None -> None
  | Some (time, _sexp) -> Some time

let reprint_build_info sexp_of_time =
  Ref.set_temporarily
    Time_float_with_limited_parsing.sexp_of_t_ref
    (fun (time, _) -> sexp_of_time time)
    ~f:(fun () -> Sexp.to_string (sexp_of_t t))

let compiled_for_speed = x_library_inlining && not dynlinkable_code
