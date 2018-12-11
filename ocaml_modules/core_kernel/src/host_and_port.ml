module Stable = struct
  open Stable_internal
  open Ppx_compare_lib.Builtin

  module V1 = struct

    module Serializable = struct
      type t = (string * int) [@@deriving sexp, bin_io]
    end

    module T = struct
      type t =
        { host : string
        ; port : int
        } [@@deriving compare, hash]

      let to_serializable {host; port} = (host, port)
      let of_serializable (host, port) = {host; port}
    end

    include T

    include Binable.Stable.Of_binable.V1 (Serializable) (struct
        include T
        let to_binable = to_serializable
        let of_binable = of_serializable
      end)

    let%expect_test "stable" =
      print_endline [%bin_digest: t];
      print_endline [%bin_digest: Serializable.t];
      [%expect {|
                  957990f0fc4161fb874e66872550fb40
                  957990f0fc4161fb874e66872550fb40 |}]
    ;;

    include Sexpable.Stable.Of_sexpable.V1 (Serializable) (struct
        include T
        let to_sexpable = to_serializable
        let of_sexpable = of_serializable
      end)
  end
end

open! Import
open Std_internal

module Latest = struct
  include Stable.V1
end
include Latest

let create ~host ~port = { host; port }

let host t = t.host
let port t = t.port
let tuple t = to_serializable t

let to_string {host; port} = sprintf "%s:%d" host port
let of_string s =
  match String.split s ~on:':' with
  | [host; port] ->
    let port =
      try Int.of_string port
      with _exn -> failwithf "Host_and_port.of_string: bad port: %s" s ()
    in
    {host; port}
  | _ -> failwithf "Host_and_port.of_string: %s" s ()

include Pretty_printer.Register (struct
    type nonrec t = t
    let to_string = to_string
    let module_name = "Core_kernel.Host_and_port"
  end)

include (Hashable.Make_binable (Latest) : Hashable.S_binable with type t := t)

include Comparable.Make_binable (Latest)

let t_of_sexp = function
  | Sexp.Atom s as sexp ->
    (try of_string s with Failure err -> of_sexp_error err sexp)
  | sexp -> t_of_sexp sexp

let type_id =
  Type_equal.Id.create ~name:"Host_and_port" sexp_of_t
;;
