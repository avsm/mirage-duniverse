(** A scale factor, not bounded between 0% and 100%, represented as a float. *)

open! Import
open Std_internal

type t [@@deriving hash]

(** [of_string] and [t_of_sexp] disallow [nan], [inf], etc. *)
include Stringable with type t := t

(** Sexps are of the form 5bp or 0.05% or 0.0005x *)
include Sexpable              with type t := t
include Binable               with type t := t
include Comparable            with type t := t
include Comparable.With_zero  with type t := t
include Robustly_comparable.S with type t := t
include Commutative_group.S   with type t := t

val ( * ) : t -> t -> t

val neg : t -> t
val abs : t -> t


val is_zero : t -> bool
val is_nan : t -> bool
val is_inf : t -> bool

(** [apply t x] multiplies the percent [t] by [x], returning a float. *)
val apply : t -> float -> float

(** [scale t x] scales the percent [t] by [x], returning a new [t]. *)
val scale : t -> float -> t

(** [of_mult 5.] is 5x = 500% = 50_000bp *)
val of_mult : float -> t
val to_mult : t -> float

(** [of_percentage 5.] is 5% = 0.05x = 500bp *)
val of_percentage : float -> t
val to_percentage : t -> float

(** [of_bp 5.] is 5bp = 0.05% = 0.0005x *)
val of_bp : float -> t
val to_bp : t -> float

val of_bp_int : int -> t
val to_bp_int : t -> int  (** rounds down *)

val t_of_sexp_allow_nan_and_inf : Sexp.t -> t
val of_string_allow_nan_and_inf : string -> t

(** A [Format.t] tells [Percent.format] how to render a floating-point value as a string,
    like a [printf] conversion specification.

    For example:

    {[
      format (Format.exponent ~precision) = sprintf "%.e" precision
    ]}

    The [_E] naming suffix in [Format] values is mnenomic of a capital [E] (rather than
    [e]) being used in floating-point exponent notation.

    Here is the documentation of the floating-point conversion specifications from the
    OCaml manual:

    - f: convert a floating-point argument to decimal notation, in the style dddd.ddd.

    - F: convert a floating-point argument to OCaml syntax (dddd. or dddd.ddd or d.ddd
      e+-dd).

    - e or E: convert a floating-point argument to decimal notation, in the style d.ddd
      e+-dd (mantissa and exponent).

    - g or G: convert a floating-point argument to decimal notation, in style f or e, E
      (whichever is more compact).

    - h or H: convert a floating-point argument to hexadecimal notation, in the style
      0xh.hhhh e+-dd (hexadecimal mantissa, exponent in decimal and denotes a power of
      2).
*)
module Format : sig
  type t [@@deriving sexp_of]

  val exponent   : precision : int -> t (** [sprintf "%.*e" precision] *)

  val exponent_E : precision : int -> t (** [sprintf "%.*E" precision] *)

  val decimal    : precision : int -> t (** [sprintf "%.*f" precision] *)

  val ocaml      :                    t (** [sprintf   "%F"          ] *)

  val compact    : precision : int -> t (** [sprintf "%.*g" precision] *)

  val compact_E  : precision : int -> t (** [sprintf "%.*G" precision] *)

  val hex        : precision : int -> t (** [sprintf "%.*h" precision] *)

  val hex_E      : precision : int -> t (** [sprintf "%.*H" precision] *)
end

val format : t -> Format.t -> string

val validate : t -> Validate.t

(*_ Caution: If we remove this sig item, [sign] will still be present from
  [Comparable.With_zero]. *)
val sign : t -> Sign.t
[@@deprecated "[since 2016-01] Replace [sign] with [sign_exn]"]

(** The sign of a [Percent.t].  Both [-0.] and [0.] map to [Zero].  Raises on nan.  All
    other values map to [Neg] or [Pos]. *)
val sign_exn : t -> Sign.t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving sexp, bin_io, compare, hash]
  end
end
