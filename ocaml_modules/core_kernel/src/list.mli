(** This module extends {{!Base.List}[Base.List]} with bin_io and quickcheck. *)

open! Import

type 'a t = 'a list [@@deriving bin_io, typerep]

module Assoc : sig
  type ('a, 'b) t = ('a, 'b) Base.List.Assoc.t [@@deriving bin_io]

  val compare : [%compare: 'a] -> [%compare: 'b] -> [%compare: ('a, 'b) t]
  [@@deprecated
    "[since 2016-06] This does not respect the equivalence class promised by List.Assoc.\n\
     Use List.compare directly if that's what you want."]

  include (module type of struct include Base.List.Assoc end
            with type ('a, 'b) t := ('a, 'b) t)
end

(** {2 The interface from Base} *)

include module type of struct include Base.List end
  with type 'a t := 'a t
  with module Assoc := Base.List.Assoc (** @open *)

(** {2 Extensions} *)

(** [stable_dedup] Same as [dedup] but maintains the order of the list and doesn't allow
    compare function to be specified (otherwise, the implementation in terms of Set.t
    would hide a heavyweight functor instantiation at each call). *)
val stable_dedup : 'a t -> 'a t

val stable_dedup_staged
  :  compare:('a -> 'a -> int)
  -> ('a list -> 'a list) Staged.t

(** Only raised in [exn_if_dup] below. *)
exception Duplicate_found of (unit -> Base.Sexp.t) * string
[@@deprecated "[since 2018-03] stop matching on Duplicate_found. [exn_if_dup] will \
               eventually raise a different and unspecified exception"]

(** [exn_if_dup ~compare ?context t ~to_sexp] raises if [t] contains a duplicate. It will
    specifically raise a [Duplicate_found] exception and use [context] as its second
    argument. O(n log n) time complexity. *)
val exn_if_dup
  :  compare:('a -> 'a -> int)
  -> ?context:string
  -> 'a t
  -> to_sexp:('a -> Base.Sexp.t)
  -> unit

(** [slice t start stop] returns a new list including elements [t.(start)] through
    [t.(stop-1)], normalized Python-style with the exception that [stop = 0] is treated as
    [stop = length t]. *)
val slice : 'a t -> int -> int -> 'a t

include Comparator.Derived with type 'a t := 'a t
include Quickcheckable.S1 with type 'a t := 'a t

val to_string : f:('a -> string) -> 'a t -> string

(** Like [gen], but never generates the empty list. *)
val gen_non_empty : 'a Quickcheck.Generator.t -> 'a t Quickcheck.Generator.t

(** Like [gen], but generates lists with the given length. *)
val gen_with_length : int -> 'a Quickcheck.Generator.t -> 'a t Quickcheck.Generator.t

(** [gen_permutations t] generates all permutations of [list].  If [t] contains duplicate
    values, then [gen_permutations t] will produce duplicate lists. *)
val gen_permutations : 'a t -> 'a t Quickcheck.Generator.t
