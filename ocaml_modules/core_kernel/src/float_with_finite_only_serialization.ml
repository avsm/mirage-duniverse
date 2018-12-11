open Ppx_compare_lib.Builtin

module Stable = struct
  open Stable_internal
  module Binable = Binable.Stable

  module V1 = struct
    exception Nan_or_inf [@@deriving sexp]

    type t = float [@@deriving compare, hash]

    let verify t =
      match Pervasives.classify_float t with
      | FP_normal
      | FP_subnormal
      | FP_zero      -> ()
      | FP_infinite
      | FP_nan       -> raise Nan_or_inf

    include Binable.Of_binable.V1 (Float) (struct
        type nonrec t = t
        let of_binable t = verify t; t
        let to_binable t = verify t; t
      end)

    let sexp_of_t = Float.sexp_of_t

    let t_of_sexp = function
      | Sexp.Atom _ as sexp ->
        let t = Float.t_of_sexp sexp in
        begin
          try
            verify t
          with e ->
            Import.of_sexp_error (Import.Exn.to_string e) sexp
        end;
        t
      | s ->
        Import.of_sexp_error "Decimal.t_of_sexp: Expected Atom, found List" s
    ;;
  end
end

include Stable.V1
