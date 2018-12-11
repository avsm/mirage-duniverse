(** This module defines interfaces used in {{!Map}[Map]}. See those docs for a description
    of the design.

    This module defines module types
    [{Creators,Accessors}{1,2,3,_generic,_with_comparator}]. It uses check functors to
    ensure that each module type is an instance of the corresponding [_generic] one.

    We must treat [Creators] and [Accessors] separately, because we sometimes need to
    choose different instantiations of their [options]. In particular, [Map] itself
    matches [Creators3_with_comparator] but [Accessors3] (without comparator).
*)

(*_ JS-only: CRs and comments about [Map] functions do not belong in this file.
  They belong next to the appropriate function in core_map.mli. *)

open! Import
open T
module Binable = Binable0

module Map = Base.Map

module Or_duplicate = Map.Or_duplicate

module With_comparator         = Map.With_comparator
module With_first_class_module = Map.With_first_class_module
module Without_comparator      = Map.Without_comparator

module Tree = Map.Using_comparator.Tree

module type Key_plain = sig
  type t [@@deriving compare, sexp_of]
end

module type Key = sig
  type t [@@deriving compare, sexp]
end

module type Key_binable = sig
  type t [@@deriving bin_io, compare, sexp]
end

module type Key_hashable = sig
  type t [@@deriving compare, hash, sexp]
end

module type Key_binable_hashable = sig
  type t [@@deriving bin_io, compare, hash, sexp]
end

module Symmetric_diff_element = struct
  type ('k, 'v) t = 'k * [ `Left of 'v | `Right of 'v | `Unequal of 'v * 'v ]
  [@@deriving bin_io, compare, sexp]
end

module type Accessors_generic = sig
  include Map.Accessors_generic

  val obs
    :  'k key Quickcheck.Observer.t
    -> 'v Quickcheck.Observer.t
    -> ('k, 'v, 'cmp) t Quickcheck.Observer.t

  val shrinker
    :  ('k, 'cmp,
        'k key Quickcheck.Shrinker.t
        -> 'v Quickcheck.Shrinker.t
        -> ('k, 'v, 'cmp) t Quickcheck.Shrinker.t
       ) options
end

module type Accessors1 = sig
  include Map.Accessors1

  val obs
    :  key Quickcheck.Observer.t
    -> 'v Quickcheck.Observer.t
    -> 'v t Quickcheck.Observer.t
  val shrinker
    :  key Quickcheck.Shrinker.t
    -> 'v Quickcheck.Shrinker.t
    -> 'v t Quickcheck.Shrinker.t
end

module type Accessors2 = sig
  include Map.Accessors2

  val obs
    :  'k Quickcheck.Observer.t
    -> 'v Quickcheck.Observer.t
    -> ('k, 'v) t Quickcheck.Observer.t
  val shrinker
    :  'k Quickcheck.Shrinker.t
    -> 'v Quickcheck.Shrinker.t
    -> ('k, 'v) t Quickcheck.Shrinker.t
end

module type Accessors3 = sig
  include Map.Accessors3

  val obs
    :  'k Quickcheck.Observer.t
    -> 'v Quickcheck.Observer.t
    -> ('k, 'v, _) t Quickcheck.Observer.t
  val shrinker
    :  'k Quickcheck.Shrinker.t
    -> 'v Quickcheck.Shrinker.t
    -> ('k, 'v, _) t Quickcheck.Shrinker.t
end

module type Accessors3_with_comparator = sig
  include Map.Accessors3_with_comparator

  val obs
    :  'k Quickcheck.Observer.t
    -> 'v Quickcheck.Observer.t
    -> ('k, 'v, 'cmp) t Quickcheck.Observer.t
  val shrinker
    :  comparator:('k, 'cmp) Comparator.t
    -> 'k Quickcheck.Shrinker.t
    -> 'v Quickcheck.Shrinker.t
    -> ('k, 'v, 'cmp) t Quickcheck.Shrinker.t
end

(** Consistency checks (same as in [Container]). *)
module Check_accessors (T : T3) (Tree : T3) (Key : T1) (Options : T3)
    (M : Accessors_generic
     with type ('a, 'b, 'c) options := ('a, 'b, 'c) Options.t
     with type ('a, 'b, 'c) t       := ('a, 'b, 'c) T.t
     with type ('a, 'b, 'c) tree    := ('a, 'b, 'c) Tree.t
     with type 'a key               := 'a Key.t)
= struct end

module Check_accessors1 (M : Accessors1) =
  Check_accessors
    (struct type ('a, 'b, 'c) t = 'b M.t end)
    (struct type ('a, 'b, 'c) t = 'b M.tree end)
    (struct type 'a t           = M.key end)
    (Without_comparator)
    (M)

module Check_accessors2 (M : Accessors2) =
  Check_accessors
    (struct type ('a, 'b, 'c) t = ('a, 'b) M.t end)
    (struct type ('a, 'b, 'c) t = ('a, 'b) M.tree end)
    (struct type 'a t           = 'a end)
    (Without_comparator)
    (M)

module Check_accessors3 (M : Accessors3) =
  Check_accessors
    (struct type ('a, 'b, 'c) t = ('a, 'b, 'c) M.t end)
    (struct type ('a, 'b, 'c) t = ('a, 'b, 'c) M.tree end)
    (struct type 'a t           = 'a end)
    (Without_comparator)
    (M)

module Check_accessors3_with_comparator (M : Accessors3_with_comparator) =
  Check_accessors
    (struct type ('a, 'b, 'c) t = ('a, 'b, 'c) M.t end)
    (struct type ('a, 'b, 'c) t = ('a, 'b, 'c) M.tree end)
    (struct type 'a t           = 'a end)
    (With_comparator)
    (M)

module type Creators_generic = sig
  include Map.Creators_generic

  val of_hashtbl_exn : ('k, 'cmp, ('k key, 'v) Hashtbl.t -> ('k, 'v, 'cmp) t) options

  val gen
    :  ('k, 'cmp,
        'k key Quickcheck.Generator.t
        -> 'v Quickcheck.Generator.t
        -> ('k, 'v, 'cmp) t Quickcheck.Generator.t
       ) options
end

module type Creators1 = sig
  include Map.Creators1

  val of_hashtbl_exn  : (key, 'a) Hashtbl.t -> 'a t

  val gen
    :  key Quickcheck.Generator.t
    -> 'a Quickcheck.Generator.t
    -> 'a t Quickcheck.Generator.t
end

module type Creators2 = sig
  include Map.Creators2

  val of_hashtbl_exn  : ('a, 'b) Hashtbl.t -> ('a, 'b) t

  val gen
    :  'a Quickcheck.Generator.t
    -> 'b Quickcheck.Generator.t
    -> ('a, 'b) t Quickcheck.Generator.t
end

module type Creators3_with_comparator = sig
  include Map.Creators3_with_comparator

  val of_hashtbl_exn
    :  comparator:('a, 'cmp) Comparator.t
    -> ('a, 'b) Hashtbl.t -> ('a, 'b, 'cmp) t

  val gen
    :  comparator:('a, 'cmp) Comparator.t
    -> 'a Quickcheck.Generator.t
    -> 'b Quickcheck.Generator.t
    -> ('a, 'b, 'cmp) t Quickcheck.Generator.t
end

module Check_creators (T : T3) (Tree : T3) (Key : T1) (Options : T3)
    (M : Creators_generic
     with type ('a, 'b, 'c) options := ('a, 'b, 'c) Options.t
     with type ('a, 'b, 'c) t       := ('a, 'b, 'c) T.t
     with type ('a, 'b, 'c) tree    := ('a, 'b, 'c) Tree.t
     with type 'a key               := 'a Key.t)
= struct end

module Check_creators1 (M : Creators1) =
  Check_creators
    (struct type ('a, 'b, 'c) t = 'b M.t end)
    (struct type ('a, 'b, 'c) t = 'b M.tree end)
    (struct type 'a t           = M.key end)
    (Without_comparator)
    (M)

module Check_creators2 (M : Creators2) =
  Check_creators
    (struct type ('a, 'b, 'c) t = ('a, 'b) M.t end)
    (struct type ('a, 'b, 'c) t = ('a, 'b) M.tree end)
    (struct type 'a t           = 'a end)
    (Without_comparator)
    (M)

module Check_creators3_with_comparator (M : Creators3_with_comparator) =
  Check_creators
    (struct type ('a, 'b, 'c) t = ('a, 'b, 'c) M.t end)
    (struct type ('a, 'b, 'c) t = ('a, 'b, 'c) M.tree end)
    (struct type 'a t           = 'a end)
    (With_comparator)
    (M)

module type Creators_and_accessors_generic = sig
  include Creators_generic
  include Accessors_generic
    with type ('a, 'b, 'c) t       := ('a, 'b, 'c) t
    with type ('a, 'b, 'c) tree    := ('a, 'b, 'c) tree
    with type 'a key               := 'a key
    with type ('a, 'b, 'c) options := ('a, 'b, 'c) options
end

module type Creators_and_accessors1 = sig
  include Creators1
  include Accessors1
    with type 'a t    := 'a t
    with type 'a tree := 'a tree
    with type key     := key
end

module type Creators_and_accessors2 = sig
  include Creators2
  include Accessors2
    with type ('a, 'b) t    := ('a, 'b) t
    with type ('a, 'b) tree := ('a, 'b) tree
end

module type Creators_and_accessors3_with_comparator = sig
  include Creators3_with_comparator
  include Accessors3_with_comparator
    with type ('a, 'b, 'c) t    := ('a, 'b, 'c) t
    with type ('a, 'b, 'c) tree := ('a, 'b, 'c) tree
end

module Make_S_plain_tree (Key : Comparator.S) = struct
  module type S = sig

    type 'a t = (Key.t, 'a, Key.comparator_witness) Tree.t
    [@@deriving sexp_of]

    include Creators_and_accessors1
      with type 'a t    := 'a t
      with type 'a tree := 'a t
      with type key     := Key.t

    module Provide_of_sexp (K : sig type t [@@deriving of_sexp] end with type t := Key.t)
      : sig type _ t [@@deriving of_sexp] end with type 'a t := 'a t
  end
end

module type S_plain = sig
  module Key : sig
    type t [@@deriving sexp_of]
    include Comparator.S with type t := t
  end

  module Tree : Make_S_plain_tree (Key).S

  type +'a t = (Key.t, 'a, Key.comparator_witness) Map.t [@@deriving compare, sexp_of]

  include Creators_and_accessors1
    with type 'a t    := 'a t
    with type 'a tree := 'a Tree.t
    with type key     := Key.t

  module Provide_of_sexp (Key : sig type t [@@deriving of_sexp] end with type t := Key.t)
    : sig type _ t [@@deriving of_sexp] end with type 'a t := 'a t
  module Provide_bin_io (Key : sig type t [@@deriving bin_io] end with type t := Key.t)
    : Binable.S1 with type 'a t := 'a t
  module Provide_hash (Key : Hasher.S with type t := Key.t)
    : sig type 'a t [@@deriving hash] end with type 'a t := 'a t
end

module type S = sig
  module Key : sig
    type t [@@deriving sexp]
    include Comparator.S with type t := t
  end
  module Tree : sig
    include Make_S_plain_tree (Key).S
    include Sexpable.S1 with type 'a t := 'a t
  end
  include S_plain with module Key := Key and module Tree := Tree
  include Sexpable.S1 with type 'a t := 'a t
end

module type S_binable = sig
  module Key : sig
    type t [@@deriving bin_io, sexp]
    include Comparator.S with type t := t
  end
  include S with module Key := Key
  include Binable.S1 with type 'a t := 'a t
end
