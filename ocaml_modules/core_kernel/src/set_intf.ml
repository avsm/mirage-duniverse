(** This module defines interfaces used in {{!Core_kernel.Set}[Set]}. See the
    {!Map} docs for a description of the design.

    This module defines module types
    [{Creators,Accessors}{0,1,2,_generic,_with_comparator}]. It uses check functors to
    ensure that each module type is an instance of the corresponding [_generic] one.

    We must treat [Creators] and [Accessors] separately, because we sometimes need to
    choose different instantiations of their [options]. In particular, [Set] itself
    matches [Creators2_with_comparator] but [Accessors2] (without comparator).
*)
(*
   CRs and comments about [Set] functions do not belong in this file.  They belong next
   to the appropriate function in core_set.mli.
*)

open! Import
open T

module Binable = Binable0

module Set = Base.Set

module Tree = Set.Using_comparator.Tree

module Named = Set.Named

module Container = Base.Container

module type Elt_plain = Set.Elt_plain

module type Elt = sig
  type t [@@deriving compare, sexp]
end

module type Elt_binable = sig
  type t [@@deriving bin_io, compare, sexp]
end

module Without_comparator      = Set.Without_comparator
module With_comparator         = Set.With_comparator
module With_first_class_module = Set.With_first_class_module

module Continue_or_stop = Container.Continue_or_stop

module Merge_to_sequence_element = Sequence.Merge_with_duplicates_element

module type Accessors_generic = sig
  include Set.Accessors_generic

  val to_map
    : ('a, 'cmp,
       ('a, 'cmp) t -> f:('a elt -> 'b) -> ('a elt, 'b, 'cmp cmp) Map.t
      ) options

  val obs : 'a elt Quickcheck.Observer.t -> ('a, 'cmp) t Quickcheck.Observer.t

  val shrinker
    : ('a, 'cmp,
       'a elt Quickcheck.Shrinker.t -> ('a, 'cmp) t Quickcheck.Shrinker.t
      ) options
end

module type Accessors0 = sig
  include Set.Accessors0
  val to_map : t -> f:(elt -> 'data) -> (elt, 'data, comparator_witness) Map.t
  val obs : elt Quickcheck.Observer.t -> t Quickcheck.Observer.t
  val shrinker : elt Quickcheck.Shrinker.t -> t Quickcheck.Shrinker.t
end

module type Accessors1 = sig
  include Set.Accessors1
  val to_map         : 'a t -> f:('a -> 'b) -> ('a, 'b, comparator_witness) Map.t
  val obs : 'a Quickcheck.Observer.t -> 'a t Quickcheck.Observer.t
  val shrinker : 'a Quickcheck.Shrinker.t -> 'a t Quickcheck.Shrinker.t
end

module type Accessors2 = sig
  include Set.Accessors2
  val to_map         : ('a, 'cmp) t -> f:('a -> 'b) -> ('a, 'b, 'cmp) Map.t
  val obs : 'a Quickcheck.Observer.t -> ('a, 'cmp) t Quickcheck.Observer.t
  val shrinker : 'a Quickcheck.Shrinker.t -> ('a, 'cmp) t Quickcheck.Shrinker.t
end

module type Accessors2_with_comparator = sig
  include Set.Accessors2_with_comparator
  val to_map
    :  comparator:('a, 'cmp) Comparator.t
    -> ('a, 'cmp) t
    -> f:('a -> 'b)
    -> ('a, 'b, 'cmp) Map.t
  val obs : 'a Quickcheck.Observer.t -> ('a, 'cmp) t Quickcheck.Observer.t
  val shrinker
    :  comparator:('a, 'cmp) Comparator.t
    -> 'a Quickcheck.Shrinker.t
    -> ('a, 'cmp) t Quickcheck.Shrinker.t
end

(** Consistency checks (same as in [Container]). *)
module Check_accessors (T : T2) (Tree : T2) (Elt : T1) (Named : T2) (Cmp : T1) (Options : T3)
    (M : Accessors_generic
     with type ('a, 'b, 'c) options := ('a, 'b, 'c) Options.t
     with type ('a, 'b) t           := ('a, 'b) T.t
     with type ('a, 'b) tree        := ('a, 'b) Tree.t
     with type 'a elt               := 'a Elt.t
     with type 'cmp cmp             := 'cmp Cmp.t
     with type ('a, 'b) named       := ('a, 'b) Named.t)
= struct end

module Check_accessors0 (M : Accessors0) =
  Check_accessors
    (struct type ('a, 'b) t = M.t end)
    (struct type ('a, 'b) t = M.tree end)
    (struct type 'a t = M.elt end)
    (struct type ('a, 'b) t = M.named end)
    (struct type 'a t = M.comparator_witness end)
    (Without_comparator)
    (M)

module Check_accessors1 (M : Accessors1) =
  Check_accessors
    (struct type ('a, 'b) t = 'a M.t end)
    (struct type ('a, 'b) t = 'a M.tree end)
    (struct type 'a t = 'a end)
    (struct type ('a, 'b) t = 'a M.named end)
    (struct type 'a t = M.comparator_witness end)
    (Without_comparator)
    (M)

module Check_accessors2 (M : Accessors2) =
  Check_accessors
    (struct type ('a, 'b) t = ('a, 'b) M.t end)
    (struct type ('a, 'b) t = ('a, 'b) M.tree end)
    (struct type 'a t = 'a end)
    (struct type ('a, 'b) t = ('a, 'b) M.named end)
    (struct type 'a t = 'a end)
    (Without_comparator)
    (M)

module Check_accessors2_with_comparator (M : Accessors2_with_comparator) =
  Check_accessors
    (struct type ('a, 'b) t = ('a, 'b) M.t end)
    (struct type ('a, 'b) t = ('a, 'b) M.tree end)
    (struct type 'a t = 'a end)
    (struct type ('a, 'b) t = ('a, 'b) M.named end)
    (struct type 'a t = 'a end)
    (With_comparator)
    (M)

module type Creators_generic = sig
  include Set.Creators_generic

  val of_hash_set     : ('a, 'cmp,  'a elt     Hash_set.t     -> ('a, 'cmp) t) options
  val of_hashtbl_keys : ('a, 'cmp, ('a elt, _) Hashtbl.t -> ('a, 'cmp) t) options

  (** Never requires a comparator because it can get one from the input [Map.t]. *)
  val of_map_keys : ('a elt, _, 'cmp cmp) Map.t -> ('a, 'cmp) t

  val gen
    : ('a, 'cmp,
       'a elt Quickcheck.Generator.t
       -> ('a, 'cmp) t Quickcheck.Generator.t
      ) options
end

module type Creators0 = sig
  include Set.Creators0
  val of_hash_set               : elt Hash_set.t  -> t
  val of_hashtbl_keys           : (elt, _) Hashtbl.t -> t
  val of_map_keys               : (elt, _, comparator_witness) Map.t -> t
  val gen                       : elt Quickcheck.Generator.t -> t Quickcheck.Generator.t
end

module type Creators1 = sig
  include Set.Creators1
  val of_hash_set               : 'a Hash_set.t  -> 'a t
  val of_hashtbl_keys           : ('a, _) Hashtbl.t -> 'a t
  val of_map_keys               : ('a, _, comparator_witness) Map.t -> 'a t
  val gen                       : 'a Quickcheck.Generator.t -> 'a t Quickcheck.Generator.t
end

module type Creators2 = sig
  include Set.Creators2
  val of_hash_set               : 'a Hash_set.t  -> ('a, 'cmp) t
  val of_hashtbl_keys           : ('a, _) Hashtbl.t -> ('a, 'cmp) t
  val of_map_keys               : ('a, _, 'cmp) Map.t -> ('a, 'cmp) t
  val gen
    :  'a Quickcheck.Generator.t
    -> ('a, 'cmp) t Quickcheck.Generator.t
end

module type Creators2_with_comparator = sig
  include Set.Creators2_with_comparator
  val of_hash_set               : comparator:('a, 'cmp) Comparator.t -> 'a Hash_set.t
    -> ('a, 'cmp) t
  val of_hashtbl_keys           : comparator:('a, 'cmp) Comparator.t
    -> ('a, _) Hashtbl.t -> ('a, 'cmp) t

  val of_map_keys : ('a, _, 'cmp) Map.t -> ('a, 'cmp) t

  val gen
    :  comparator:('a, 'cmp) Comparator.t
    -> 'a Quickcheck.Generator.t
    -> ('a, 'cmp) t Quickcheck.Generator.t
end

module Check_creators (T : T2) (Tree : T2) (Elt : T1) (Cmp : T1) (Options : T3)
    (M : Creators_generic
     with type ('a, 'b, 'c) options := ('a, 'b, 'c) Options.t
     with type ('a, 'b) t           := ('a, 'b) T.t
     with type ('a, 'b) tree        := ('a, 'b) Tree.t
     with type 'a elt               := 'a Elt.t
     with type 'cmp cmp             := 'cmp Cmp.t)
= struct end

module Check_creators0 (M : Creators0) =
  Check_creators
    (struct type ('a, 'b) t = M.t end)
    (struct type ('a, 'b) t = M.tree end)
    (struct type 'a t = M.elt end)
    (struct type 'cmp t = M.comparator_witness end)
    (Without_comparator)
    (M)

module Check_creators1 (M : Creators1) =
  Check_creators
    (struct type ('a, 'b) t = 'a M.t end)
    (struct type ('a, 'b) t = 'a M.tree end)
    (struct type 'a t = 'a end)
    (struct type 'cmp t = M.comparator_witness end)
    (Without_comparator)
    (M)

module Check_creators2 (M : Creators2) =
  Check_creators
    (struct type ('a, 'b) t = ('a, 'b) M.t end)
    (struct type ('a, 'b) t = ('a, 'b) M.tree end)
    (struct type 'a t = 'a end)
    (struct type 'cmp t = 'cmp end)
    (Without_comparator)
    (M)

module Check_creators2_with_comparator (M : Creators2_with_comparator) =
  Check_creators
    (struct type ('a, 'b) t = ('a, 'b) M.t end)
    (struct type ('a, 'b) t = ('a, 'b) M.tree end)
    (struct type 'a t = 'a end)
    (struct type 'cmp t = 'cmp end)
    (With_comparator)
    (M)

module type Creators_and_accessors_generic = sig
  include Accessors_generic
  include Creators_generic
    with type ('a, 'b, 'c) options := ('a, 'b, 'c) options
    with type ('a, 'b) t           := ('a, 'b) t
    with type ('a, 'b) tree        := ('a, 'b) tree
    with type 'a elt               := 'a elt
    with type 'cmp cmp             := 'cmp cmp
end

module type Creators_and_accessors0 = sig
  include Accessors0
  include Creators0
    with type t    := t
    with type tree := tree
    with type elt  := elt
    with type comparator_witness := comparator_witness
end

module type Creators_and_accessors1 = sig
  include Accessors1
  include Creators1
    with type 'a t    := 'a t
    with type 'a tree := 'a tree
    with type comparator_witness := comparator_witness
end

module type Creators_and_accessors2 = sig
  include Accessors2
  include Creators2
    with type ('a, 'b) t    := ('a, 'b) t
    with type ('a, 'b) tree := ('a, 'b) tree
end

module type Creators_and_accessors2_with_comparator = sig
  include Accessors2_with_comparator
  include Creators2_with_comparator
    with type ('a, 'b) t    := ('a, 'b) t
    with type ('a, 'b) tree := ('a, 'b) tree
end

module Make_S_plain_tree (Elt : Comparator.S) = struct
  module type S = sig
    type t = (Elt.t, Elt.comparator_witness) Tree.t
    [@@deriving compare, sexp_of]

    type named = (Elt.t, Elt.comparator_witness) Tree.Named.t
    include Creators_and_accessors0
      with type ('a, 'b) set := ('a, 'b) Tree.t
      with type t            := t
      with type tree         := t
      with type elt          := Elt.t
      with type named        := named
      with type comparator_witness := Elt.comparator_witness

    module Provide_of_sexp (Elt : sig type t [@@deriving of_sexp] end with type t := Elt.t)
      : sig type t [@@deriving of_sexp] end with type t := t
  end
end

module type S_plain = sig
  module Elt : sig
    type t [@@deriving sexp_of]
    include Comparator.S with type t := t
  end
  module Tree : Make_S_plain_tree (Elt).S

  type t = (Elt.t, Elt.comparator_witness) Base.Set.t [@@deriving compare, sexp_of]

  type named = (Elt.t, Elt.comparator_witness) Named.t
  include Creators_and_accessors0
    with type ('a, 'b) set := ('a, 'b) Base.Set.t
    with type t            := t
    with type tree         := Tree.t
    with type elt          := Elt.t
    with type named        := named
    with type comparator_witness := Elt.comparator_witness

  module Provide_of_sexp (Elt : sig type t [@@deriving of_sexp] end with type t := Elt.t)
    : sig type t [@@deriving of_sexp] end with type t := t
  module Provide_bin_io (Elt : sig type t [@@deriving bin_io] end with type t := Elt.t)
    : Binable.S with type t := t
  module Provide_hash (Elt : Hasher.S with type t := Elt.t)
    : sig type t [@@deriving hash] end with type t := t
end

module type S = sig
  module Elt : sig
    type t [@@deriving sexp]
    include Comparator.S with type t := t
  end
  module Tree : sig
    include Make_S_plain_tree (Elt).S
    include Sexpable.S with type t := t
  end
  include S_plain with module Elt := Elt and module Tree := Tree
  include Sexpable.S with type t := t
end

module type S_binable = sig
  module Elt : sig
    type t [@@deriving sexp, bin_io]
    include Comparator.S with type t := t
  end
  include S with module Elt := Elt
  include Binable.S with type t := t
end
