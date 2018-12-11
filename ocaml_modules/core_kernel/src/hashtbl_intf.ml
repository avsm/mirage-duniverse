(** Hashtbl is a reimplementation of the standard {{:
    https://caml.inria.fr/pub/docs/manual-ocaml/libref/MoreLabels.Hashtbl.html}[MoreLabels.Hashtbl]}. Its
    worst case time complexity is O(log(N)) for lookups and additions, unlike the standard
    [MoreLabels.Hashtbl], which is O(N).

    A hash table is implemented as an array of AVL trees (see [Avltree]). If
    [growth_allowed] (default true) is false then [size] is the final size of the array;
    the table can always hold more elements than [size], but they will all go into
    tree nodes. If it is true (default) then the array will double in size when the number
    of elements in the table reaches twice the size of the array. When this happens, all
    existing elements will be reinserted, which can take a long time. If you care about
    latency, set [size] and [growth_allowed=false] if possible.

    In most cases, functions passed as arguments to hash table accessors must not mutate
    the hash table while it is being accessed, as this will result in an exception. For
    example, [iter] and [change] take a function [f] which must not modify [t]. In a few
    cases, mutation is allowed, such as in [Hashtbl.find_and_call], where all access to
    [t] is finished before the [~if_found] and [~if_not_found] arguments are invoked.

    We have three kinds of hash table modules:
    - [Hashtbl]
    - [Hashtbl.Poly]
    - [Key.Table] (a class of similar modules)

    There are three kinds of hash-table functions:
    - creation from nothing ([create], [of_alist])
    - sexp converters ([t_of_sexp], [sexp_of_t], and [bin_io] too)
    - accessors and mappers ([fold], [mem], [find], [map], [filter_map], ...)

    Here is a table showing what classes of functions are available in each kind
    of hash-table module:
    {v
                   creation     sexp-conv   accessors
    Hashtbl                                   X
    Hashtbl.Poly      X           X
    Key.Table         X           X           X'
    v}

    The entry marked with [X'] is there for historical reasons, and may be eliminated at
    some point. The upshot is that one should use [Hashtbl] for accessors, [Hashtbl.Poly]
    for hash-table creation and sexp conversion using polymorphic compare/hash, and
    [Key.Table] for hash-table creation and sexp conversion using [Key.compare] and
    [Key.hash].

    {2:usage Usage}

    For many students of OCaml, using hashtables is complicated by the
    functors.  Here are a few tips:

    {ol
    {- For a list of hashtable functions see {!Core_kernel.Hashtbl_intf.S}.}

    {- To create a hashtable with string keys use [String.Table]:
    {[
      let table = String.Table.create () ~size:4 in
      List.iter ~f:(fun (key, data) -> Hashtbl.set table ~key ~data)
        [ ("A", 1); ("B", 2); ("C", 3); ];
      Hashtbl.find table "C"
    ]}

    Here 4 need only be a guess at the hashtable's future size. There are other similar
    pre-made hashtables, e.g., [Int63.Table] or [Host_and_port.Table].
    }

    {- To create a hashtable with a custom key type use Hashable:
    {[
      module Key = struct
        module T = struct
          type t = String.t * Int63.t [@@deriving compare, hash, sexp]
        end
        include T
        include Hashable.Make (T)
      end
      let table = Key.Table.create () ~size:4 in
      List.iter ~f:(fun (key, data) -> Hashtbl.set table ~key ~data)
        [ (("pi", Int63.zero), 3.14159);
          (("e", Int63.minus_one), 2.71828);
          (("Euler", Int63.one), 0.577215);
        ];
      Hashtbl.find table ("pi", Int63.zero)
    ]}

    Performance {i may} improve if you define [equal] and [hash] explicitly, e.g.:

    {[
      let equal (x, y) (x', y') = String.(=) x x' && Int63.(=) y y'
      let hash (x, y) = String.hash x + Int63.hash y * 65599
    ]}
    }
    }
*)

open! Import

module Binable = Binable0

module Hashtbl = Base.Hashtbl

module type Key_plain  = Hashtbl.Key

module      Hashable = Base.Hashable
module type Hashable = Base.Hashable.Hashable

module type Key = sig
  type t [@@deriving sexp]
  include Key_plain with type t := t
end

module type Key_binable = sig
  type t [@@deriving bin_io, sexp]
  include Key with type t := t
end

module type Creators  = Hashtbl.Private.Creators_generic
module type Accessors = Hashtbl.Accessors
module type Multi     = Hashtbl.Multi

type ('key, 'data, 'z) create_options_with_first_class_module =
  ('key, 'data, 'z) Hashtbl.create_options

type ('key, 'data, 'z) create_options_without_hashable =
  ('key, 'data, 'z) Hashtbl.Private.create_options_without_first_class_module

type ('key, 'data, 'z) create_options_with_hashable =
  ?growth_allowed:bool (** defaults to [true] *)
  -> ?size:int (** initial size -- default 128 *)
  -> hashable:'key Hashable.t
  -> 'z

module type S_plain = sig
  type key
  type ('a, 'b) hashtbl
  type 'b t = (key, 'b) hashtbl [@@deriving sexp_of]
  type ('a, 'b) t_ = 'b t
  type 'a key_ = key

  val hashable : key Hashable.t

  include Invariant.S1 with type 'b t := 'b t

  include Creators
    with type ('a, 'b) t := ('a, 'b) t_
    with type 'a key := 'a key_
    with type ('key, 'data, 'z) create_options := ('key, 'data, 'z) create_options_without_hashable

  include Accessors
    with type ('a, 'b) t := ('a, 'b) t_
    with type 'a key := 'a key_

  include Multi
    with type ('a, 'b) t := ('a, 'b) t_
    with type 'a key := 'a key_

  module Provide_of_sexp (Key : sig type t [@@deriving of_sexp] end with type t := key)
    : sig type _ t [@@deriving of_sexp] end with type 'a t := 'a t
  module Provide_bin_io (Key : sig type t [@@deriving bin_io] end with type t := key)
    : sig type 'a t [@@deriving bin_io] end with type 'a t := 'a t
end

module type S = sig
  include S_plain
  include sig
    type _ t [@@deriving of_sexp]
  end with type 'a t := 'a t
end

module type S_binable = sig
  include S
  include Binable.S1 with type 'v t := 'v t
end

module type Hashtbl = sig
  include Hashtbl.S_without_submodules (** @inline *)

  module Using_hashable : sig
    include Creators
      with type ('a, 'b) t  := ('a, 'b) t
      with type 'a key := 'a key
      with type ('a, 'b, 'z) create_options := ('a, 'b, 'z) create_options_with_hashable
  end

  module Poly : sig
    type nonrec ('a, 'b) t = ('a, 'b) t [@@deriving bin_io]
    include Hashtbl.S_poly with type ('a, 'b) t := ('a, 'b) t
  end

  module type Key_plain   = Key_plain
  module type Key         = Key
  module type Key_binable = Key_binable

  module type S_plain   = S_plain   with type ('a, 'b) hashtbl = ('a, 'b) t
  module type S         = S         with type ('a, 'b) hashtbl = ('a, 'b) t
  module type S_binable = S_binable with type ('a, 'b) hashtbl = ('a, 'b) t

  module Make_plain   (Key : Key_plain)   : S_plain   with type key = Key.t
  module Make         (Key : Key        ) : S         with type key = Key.t
  module Make_binable (Key : Key_binable) : S_binable with type key = Key.t
  module M (K : Base.T.T) : sig
    type nonrec 'v t = (K.t, 'v) t
  end

  module Hashable = Hashable
  val hashable : ('key, _) t -> 'key Hashable.t

  val iter_vals : (_, 'b) t -> f:('b -> unit) -> unit
  [@@deprecated "[since 2016-04] Use iter instead"]

  val replace : ('a, 'b) t -> key:'a key -> data:'b -> unit
  [@@deprecated "[since 2015-10] Use set instead"]

  val replace_all : (_, 'b) t -> f:('b -> 'b) -> unit
  [@@deprecated "[since 2016-02] Use map_inplace instead"]
  val replace_alli : ('a, 'b) t -> f:(key:'a key -> data:'b -> 'b) -> unit
  [@@deprecated "[since 2016-02] Use mapi_inplace instead"]
  val filter_replace_all : (_, 'b) t -> f:('b -> 'b option) -> unit
  [@@deprecated "[since 2016-02] Use filter_map_inplace instead"]
  val filter_replace_alli : ('a, 'b) t -> f:(key:'a key -> data:'b -> 'b option) -> unit
  [@@deprecated "[since 2016-02] Use filter_mapi_inplace instead"]
end
