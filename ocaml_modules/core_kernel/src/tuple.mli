(** Functors and signatures for dealing with modules for tuples.  *)

open! Import

(** Signature for a 2-tuple module *)
module T2 : sig
  type ('a, 'b) t = 'a * 'b [@@deriving sexp, typerep]

  include Comparator.Derived2 with type ('a, 'b) t := ('a, 'b) t

  val create : 'a -> 'b -> ('a, 'b) t
  val curry :  (('a, 'b) t -> 'c) -> 'a -> 'b -> 'c
  val uncurry : ('a -> 'b -> 'c) -> ('a, 'b) t -> 'c
  val compare
    :  cmp1:('a -> 'a -> int)
    -> cmp2:('b -> 'b -> int)
    -> ('a, 'b) t
    -> ('a, 'b) t
    -> int
  val equal
    :  eq1:('a -> 'a -> bool)
    -> eq2:('b -> 'b -> bool)
    -> ('a, 'b) t -> ('a, 'b) t -> bool

  external get1 : ('a, _) t -> 'a = "%field0"
  external get2 : (_, 'a) t -> 'a = "%field1"

  val map1 : f:('a -> 'c) -> ('a, 'b) t -> ('c, 'b) t
  [@@deprecated "[since 2015-12] use map_fst"]
  val map2 : f:('b -> 'c) -> ('a, 'b) t -> ('a, 'c) t
  [@@deprecated "[since 2015-12] use map_snd"]

  val map_fst : ('a, 'b) t -> f:('a -> 'c) -> ('c, 'b) t
  val map_snd : ('a, 'b) t -> f:('b -> 'c) -> ('a, 'c) t

  val swap : ('a, 'b) t -> ('b, 'a) t
end

(** Signature for a 3-tuple module *)
module T3 : sig
  type ('a, 'b, 'c) t = 'a * 'b * 'c [@@deriving sexp, typerep]

  val create : 'a -> 'b -> 'c -> ('a, 'b, 'c) t
  val curry :  (('a, 'b, 'c) t -> 'd) -> 'a -> 'b -> 'c -> 'd
  val uncurry : ('a -> 'b -> 'c -> 'd) -> ('a, 'b, 'c) t -> 'd
  val equal
    :  eq1:('a -> 'a -> bool)
    -> eq2:('b -> 'b -> bool)
    -> eq3:('c -> 'c -> bool)
    -> ('a, 'b, 'c) t -> ('a, 'b, 'c) t -> bool
  val compare
    :  cmp1:('a -> 'a -> int)
    -> cmp2:('b -> 'b -> int)
    -> cmp3:('c -> 'c -> int)
    -> ('a, 'b, 'c) t -> ('a, 'b, 'c) t -> int
  external get1 : ('a, _, _) t -> 'a = "%field0"
  external get2 : (_, 'a, _) t -> 'a = "%field1"
  val get3 : (_, _, 'a) t -> 'a

  val map1 : f:('a -> 'd) -> ('a, 'b, 'c) t -> ('d, 'b, 'c) t
  [@@deprecated "[since 2015-12] use map_fst"]
  val map2 : f:('b -> 'd) -> ('a, 'b, 'c) t -> ('a, 'd, 'c) t
  [@@deprecated "[since 2015-12] use map_snd"]
  val map3 : f:('c -> 'd) -> ('a, 'b, 'c) t -> ('a, 'b, 'd) t
  [@@deprecated "[since 2015-12] use map_trd"]

  val map_fst : ('a, 'b, 'c) t -> f:('a -> 'd) -> ('d, 'b, 'c) t
  val map_snd : ('a, 'b, 'c) t -> f:('b -> 'd) -> ('a, 'd, 'c) t
  val map_trd : ('a, 'b, 'c) t -> f:('c -> 'd) -> ('a, 'b, 'd) t
end

(** These functors allow users to write:
    {[
      module Foo = struct
        include Tuple.Make       (String) (Int)
        include Tuple.Comparable (String) (Int)
        include Tuple.Hashable   (String) (Int)
        include Tuple.Binable    (String) (Int)
      end
    ]}
*)

module Make (T1 : sig type t end) (T2 : sig type t end) : sig type t = T1.t * T2.t end

module type Comparable_sexpable = sig
  type t [@@deriving sexp]
  include Comparable.S with type t := t
end

module Comparable (S1 : Comparable_sexpable) (S2 : Comparable_sexpable)
  : Comparable_sexpable with type t := Make (S1) (S2).t

module type Hashable_sexpable = sig
  type t [@@deriving sexp]
  include Hashable.S with type t := t
end

(** The difference between [Hashable] and [Hashable_t] functors is that the former's
    result type doesn't contain type [t] and the latter does. Therefore, [Hashable] can't
    be used to combine two pairs into 4-tuple. but [Hashable_t] can. On the other hand
    result of [Hashable_t] cannot be combined with [Comparable].

    example:
    module Four_ints = Tuple.Hashable_t (Tuple.Hashable_t (Int)(Int))
    (Tuple.Hashable_t (Int)(Int))

    If instead we used [Hashable] compiler would complain that the input to outer functor
    doesn't have type [t].

    On the other hand:
    module Foo = struct
    type t = String.t * Int.t
    include Tuple.Comparable (String) (Int)
    include Tuple.Hashable (String) (Int)
    end

    If we used [Hashable_t] above, the compiler would complain that we have two types [t]
    defined.

    Unfortunately, it is not possible to define just one functor that could be used in
    both cases.
*)
module Hashable (S1 : Hashable_sexpable) (S2 : Hashable_sexpable)
  : Hashable_sexpable with type t := Make (S1) (S2).t

module Hashable_t (S1 : Hashable_sexpable) (S2 : Hashable_sexpable)
  : Hashable_sexpable with type t = Make (S1) (S2).t

module Sexpable (S1 : Sexpable.S) (S2 : Sexpable.S)
  : Sexpable.S with type t := Make (S1) (S2).t

module Binable (B1 : Binable.S) (B2 : Binable.S)
  : Binable.S with type t := Make (B1) (B2).t

module Hasher
    (H1 : sig type t [@@deriving compare, hash, sexp] end)
    (H2 : sig type t [@@deriving compare, hash, sexp] end)
  : Hashable_sexpable with type t := Make (H1) (H2).t
