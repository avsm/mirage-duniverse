(** This module extends {{!Base.Int_intf}[Base.Int_intf]}. *)

module type Round = Base.Int.Round

module type Stable = sig
  module V1 : Stable_comparable.V1
end

module type Hexable = sig
  type t
  module Hex : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, hash, typerep]

    include Base.Stringable.S with type t := t

    val to_string_hum : ?delimiter:char -> t -> string
  end
end

module type Extension = sig
  type t [@@deriving bin_io, typerep]

  include Hexable              with type t := t
  include Identifiable.S       with type t := t
  include Quickcheckable.S_int with type t := t
end

module type S_unbounded = sig
  include Extension
  include Base.Int.S_unbounded
    with type t := t
    with type comparator_witness := comparator_witness
    with module Hex := Hex
end

module type S = sig
  include Extension
  include Base.Int.S
    with type t := t
    with type comparator_witness := comparator_witness
    with module Hex := Hex
end

module type Extension_with_stable = sig
  include Extension
  module Stable : Stable
    with type V1.t = t
     and type V1.comparator_witness = comparator_witness
end
