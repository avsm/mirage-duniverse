open! Import

module Stable = struct
  module V1 = struct
    type t = Base.Source_code_position.t =
      { pos_fname : string;
        pos_lnum : int;
        pos_bol : int;
        pos_cnum : int;
      }
    [@@deriving bin_io, compare, hash, sexp]
    include (Base.Source_code_position : Base.Comparator.S
             with type t := t
             with type comparator_witness = Base.Source_code_position.comparator_witness)
  end
end

include Stable.V1

let to_string = Base.Source_code_position.to_string
let sexp_of_t = Base.Source_code_position.sexp_of_t
