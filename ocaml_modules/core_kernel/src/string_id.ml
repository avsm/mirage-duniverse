open! Import
open Std_internal

include String_id_intf

module Make_with_validate_without_pretty_printer (M : sig
    val module_name : string
    val validate : string -> unit Or_error.t
  end) () = struct

  module Stable = struct
    module V1 = struct
      module T = struct
        type t = string
        [@@deriving sexp, compare, hash]

        let check_for_whitespace =
          let invalid s reason =
            Error (sprintf "'%s' is not a valid %s because %s" s M.module_name reason)
          in
          fun s ->
            let len = String.length s in
            if Int.(=) len 0
            then invalid s "it is empty"
            else if Char.is_whitespace s.[0] || Char.is_whitespace s.[len-1]
            then invalid s "it has whitespace on the edge"
            else Ok ()
        ;;

        let validate s =
          Result.map_error (M.validate s) ~f:Error.to_string_mach
        ;;

        let check s =
          match check_for_whitespace s with
          | Ok ()       -> validate s
          | Error error -> Error error
        ;;

        let to_string = Fn.id
        let pp = String.pp

        let of_string s =
          match check s with
          | Ok ()     -> s
          | Error err -> invalid_arg err
        ;;

        let t_of_sexp sexp =
          let s = String.Stable.V1.t_of_sexp sexp in
          match check s with
          | Ok ()     -> s
          | Error err -> of_sexp_error err sexp
        ;;

        include Binable.Of_binable (String)
            (struct
              type nonrec t = t
              let to_binable = Fn.id
              let of_binable = of_string
            end)
      end

      module T_with_comparator = struct
        include T
        include Comparator.Stable.V1.Make (T)
      end

      include T_with_comparator

      include Comparable.Stable.V1.Make          (T_with_comparator)
      include Stable_containers.Hashable.V1.Make (T_with_comparator)

    end
  end

  module Stable_latest = Stable.V1

  include Stable_latest.T_with_comparator
  include Comparable.Make_binable_using_comparator (Stable_latest.T_with_comparator)
  include Hashable.Make_binable                    (Stable_latest.T_with_comparator)
end

module Make_without_pretty_printer (M : sig val module_name : string end) () = struct
  include Make_with_validate_without_pretty_printer (struct
      let module_name = M.module_name
      let validate = Fn.const (Ok ())
    end) ()
end

module Make_with_validate (M : sig
    val module_name : string
    val validate : string -> unit Or_error.t
  end) () = struct

  include Make_with_validate_without_pretty_printer(M) ()

  include Pretty_printer.Register (struct
      type nonrec t = t
      let module_name = M.module_name
      let to_string = to_string
    end)
end

module Make (M : sig val module_name : string end) () = struct
  include Make_without_pretty_printer(M) ()

  include Pretty_printer.Register (struct
      type nonrec t = t
      let module_name = M.module_name
      let to_string = to_string
    end)
end

include Make (struct let module_name = "Core_kernel.String_id" end) ()
