(** Floating-point numbers. *)

open! Import

type t = float [@@deriving typerep]

module Robust_compare : sig
  module type S = sig
    (** intended to be a tolerance on human-entered floats *)
    val robust_comparison_tolerance : float
    include Robustly_comparable.S with type t := float
  end

  module Make (T : sig val robust_comparison_tolerance : float end) : S
end

(** The results of robust comparisons on [nan] should be considered undefined. *)
include Robust_compare.S

module O : sig
  include module type of struct include Base.Float.O end
  include Robustly_comparable.S with type t := t
end

module Terse : sig
  type nonrec t = t [@@deriving bin_io]
  include module type of struct include Base.Float.Terse end
  with type t := t
end

include Identifiable.S
  with type t := t
   and type comparator_witness := Base.Float.comparator_witness

include module type of struct include Base.Float end
  with type t := t
  with module O := Base.Float.O
  with module Terse := Base.Float.Terse

(** [to_string_12 x] builds a string representing [x] using up to 12 significant digits.
    It loses precision.  You can use ["%{Float#12}"] in formats, but consider ["%.12g"],
    ["%{Float#hum}"], or ["%{Float}"] as alternatives.  *)
val to_string_12 : t -> string

(** [to_string x] builds a string [s] representing the float [x] that guarantees the round
    trip, i.e., [Float.equal x (Float.of_string s)].

    It usually yields as few significant digits as possible.  That is, it won't print
    [3.14] as [3.1400000000000001243].  The only exception is that occasionally it will
    output 17 significant digits when the number can be represented with just 16 (but
    not 15 or fewer) of them. *)
val to_string : t -> string

val to_string_round_trippable : t -> string
[@@deprecated "[since 2017-04] Use [Float.to_string]"]

include Quickcheckable.S with type t := t

(*_ Caution: If we remove this sig item, [sign] will still be present from
  [Comparable.With_zero]. *)
val sign : t -> Sign.t
[@@deprecated "[since 2016-01] Replace [sign] with [robust_sign] or [sign_exn]"]

(** (Formerly [sign]) Uses robust comparison (so sufficiently small numbers are mapped
    to [Zero]).  Also maps NaN to [Zero]. Using this function is weakly discouraged. *)
val robust_sign : t -> Sign.t

(** [gen_uniform_excl lo hi] creates a Quickcheck generator producing finite [t] values
    between [lo] and [hi], exclusive.  The generator approximates a uniform distribution
    over the interval (lo, hi).  Raises an exception if [lo] is not finite, [hi] is not
    finite, or the requested range is empty.

    The implementation chooses values uniformly distributed between 0 (inclusive) and 1
    (exclusive) up to 52 bits of precision, then scales that interval to the requested
    range.  Due to rounding errors and non-uniform floating point precision, the resulting
    distribution may not be precisely uniform and may not include all values between [lo]
    and [hi].
*)
val gen_uniform_excl : t -> t -> t Quickcheck.Generator.t

(** [gen_incl lo hi] creates a Quickcheck generator that produces values between [lo] and
    [hi], inclusive, approximately uniformly distributed, with extra weight given to
    generating the endpoints [lo] and [hi].  Raises an exception if [lo] is not finite,
    [hi] is not finite, or the requested range is empty. *)
val gen_incl : t -> t -> t Quickcheck.Generator.t


(** [gen_finite] produces all finite [t] values, excluding infinities and all NaN
    values. *)
val gen_finite : t Quickcheck.Generator.t

(** [gen_positive] produces all (strictly) positive finite [t] values. *)
val gen_positive : t Quickcheck.Generator.t

(** [gen_negative] produces all (strictly) negative finite [t] values. *)
val gen_negative : t Quickcheck.Generator.t

(** [gen_without_nan] produces all finite and infinite [t] values, excluding all NaN
    values. *)
val gen_without_nan : t Quickcheck.Generator.t
