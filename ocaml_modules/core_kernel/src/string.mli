(** This module extends {{!Base.String}[Base.String]}. *)

type t = string [@@deriving bin_io, typerep]

module Caseless : sig
  type nonrec t = t [@@deriving bin_io, hash, sexp]

  include Comparable.S_binable with type t := t
  include Hashable.S_binable   with type t := t

  val is_suffix : t -> suffix:t -> bool
  val is_prefix : t -> prefix:t -> bool
end

include module type of struct include Base.String end
  with type t := t
  with module Caseless := Base.String.Caseless (** @open *)

(** [slice t start stop] returns a new string including elements [t.(start)] through
    [t.(stop-1)], normalized Python-style with the exception that [stop = 0] is treated as
    [stop = length t]. *)
val slice : t -> int -> int -> t

(** [nget s i] gets the char at normalized position [i] in [s]. *)
val nget : t -> int -> char

(** [take_while s ~f] returns the longest prefix of [s] satisfying [for_all prefix ~f]
    (See [lstrip] to drop such a prefix) *)
val take_while : t -> f:(char -> bool) -> t

(** [rtake_while s ~f] returns the longest suffix of [s] satisfying [for_all suffix ~f]
    (See [rstrip] to drop such a suffix) *)
val rtake_while : t -> f:(char -> bool) -> t

include Hexdump.S        with type t := t
include Identifiable.S   with type t := t and type comparator_witness := comparator_witness
include Quickcheckable.S with type t := t

(** Like [gen], but generate strings with the given distribution of characters. *)
val gen' : char Quickcheck.Generator.t -> t Quickcheck.Generator.t

(** Like [gen'], but generate strings with the given length. *)
val gen_with_length : int -> char Quickcheck.Generator.t -> t Quickcheck.Generator.t

(** Note that [string] is already stable by itself, since as a primitive type it is an
    integral part of the sexp / bin_io protocol. [String.Stable] exists only to introduce
    [String.Stable.Set] and [String.Stable.Map], and provide interface uniformity with
    other stable types. *)
module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving hash]
    include Stable_comparable.V1
      with type t := t
      with type comparator_witness = comparator_witness
  end
end
