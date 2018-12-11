open! Import
open Perms.Export
module Array = Base.Array
module Core_sequence = Sequence

type 'a t = 'a array [@@deriving bin_io, typerep]

include (Base.Array : sig
           type 'a t = 'a array [@@deriving sexp, compare]
         end with type 'a t := 'a t)

module Private = Base.Array.Private

module T = struct
  include Base.Array

  let normalize t i =
    Ordered_collection_common.normalize ~length_fun:length t i

  let slice t start stop =
    Ordered_collection_common.slice ~length_fun:length ~sub_fun:sub
      t start stop

  let nget t i =
    t.(normalize t i)

  let nset t i v =
    t.(normalize t i) <- v

  module Sequence = struct
    open Base.Array
    let length = length
    let get    = get
    let set    = set
  end

  (* See OCaml perf notes for why these array blits are special cased -- in particular,
     the section entitled "Fast, Slow and Incorrect Array blits" of
     https://janestreet.github.io/ocaml-perf-notes.html *)
  module Int = struct

    type t_ = int array [@@deriving bin_io, compare, sexp]

    module Unsafe_blit = struct
      external unsafe_blit
        : src:t_ -> src_pos:int -> dst:t_ -> dst_pos:int -> len:int -> unit
        = "core_array_unsafe_int_blit" [@@noalloc]
    end

    include
      Test_blit.Make_and_test
        (struct
          type t = int
          let equal = (=)
          let of_bool b = if b then 1 else 0
        end)
        (struct
          type t = t_ [@@deriving sexp_of]
          include Sequence
          let create ~len = create ~len 0
          include Unsafe_blit
        end)
    ;;

    include Unsafe_blit

  end

  module Float = struct

    type t_ = float array [@@deriving bin_io, compare, sexp]

    module Unsafe_blit = struct
      external unsafe_blit
        : src:t_ -> src_pos:int -> dst:t_ -> dst_pos:int -> len:int -> unit
        = "core_array_unsafe_float_blit" [@@noalloc]
    end

    include
      Test_blit.Make_and_test
        (struct
          type t = float
          let equal = Base.Float.equal
          let of_bool b = if b then 1. else 0.
        end)
        (struct
          type t = t_ [@@deriving sexp_of]
          include Sequence
          let create ~len = create ~len 0.
          include Unsafe_blit
        end)
    ;;

    include Unsafe_blit

  end
end

module type Permissioned = sig
  type ('a, -'perms) t

  include Container.        S1_permissions with type ('a, 'perms) t := ('a, 'perms) t
  include Blit.             S1_permissions with type ('a, 'perms) t := ('a, 'perms) t
  include Binary_searchable.S1_permissions with type ('a, 'perms) t := ('a, 'perms) t

  val length   : (_, _) t -> int
  val is_empty : (_, _) t -> bool

  external get : ('a, [> read]) t -> int -> 'a = "%array_safe_get"
  external set : ('a, [> write]) t -> int -> 'a -> unit = "%array_safe_set"
  external unsafe_get : ('a, [> read]) t -> int -> 'a = "%array_unsafe_get"
  external unsafe_set : ('a, [> write]) t -> int -> 'a -> unit = "%array_unsafe_set"

  val create : len:int -> 'a -> ('a, [< _ perms]) t
  val init : int -> f:(int -> 'a) -> ('a, [< _ perms]) t
  val make_matrix
    :  dimx:int
    -> dimy:int
    -> 'a
    -> (('a, [< _ perms]) t, [< _ perms]) t
  val append : ('a, [> read]) t -> ('a, [> read]) t -> ('a, [< _ perms]) t
  val concat : ('a, [> read]) t list -> ('a, [< _ perms]) t
  val copy : ('a, [> read]) t -> ('a, [< _ perms]) t
  val fill : ('a, [> write]) t -> pos:int -> len:int -> 'a -> unit
  val of_list : 'a list -> ('a, [< _ perms]) t
  val map : ('a, [> read]) t -> f:('a -> 'b) -> ('b, [< _ perms]) t
  val folding_map
    :  ('a, [> read]) t
    -> init:'b
    -> f:('b -> 'a -> 'b * 'c)
    -> ('c, [< _ perms]) t
  val fold_map
    :  ('a, [> read]) t
    -> init:'b
    -> f:('b -> 'a -> 'b * 'c)
    -> 'b * ('c, [< _ perms]) t
  val mapi : ('a, [> read]) t -> f:(int -> 'a -> 'b) -> ('b, [< _ perms]) t
  val iteri : ('a, [> read]) t -> f:(int -> 'a -> unit) -> unit
  val foldi : ('a, [> read]) t -> init:'b -> f:(int -> 'b -> 'a -> 'b) -> 'b
  val folding_mapi
    :  ('a, [> read]) t
    -> init:'b
    -> f:(int -> 'b -> 'a -> 'b * 'c)
    -> ('c, [< _ perms]) t
  val fold_mapi
    :  ('a, [> read]) t
    -> init:'b
    -> f:(int -> 'b -> 'a -> 'b * 'c)
    -> 'b * ('c, [< _ perms]) t
  val fold_right : ('a, [> read]) t -> f:('a -> 'b -> 'b) -> init:'b -> 'b
  val sort
    :  ?pos:int
    -> ?len:int
    -> ('a, [> read_write]) t
    -> compare:('a -> 'a -> int)
    -> unit
  val stable_sort : ('a, [> read_write]) t -> compare:('a -> 'a -> int) -> unit
  val is_sorted : ('a, [> read]) t -> compare:('a -> 'a -> int) -> bool
  val is_sorted_strictly : ('a, [> read]) t -> compare:('a -> 'a -> int) -> bool
  val concat_map
    :  ('a, [> read]) t
    -> f:('a -> ('b, [> read]) t)
    -> ('b, [< _ perms]) t
  val concat_mapi
    :  ('a, [> read]) t
    -> f:(int -> 'a -> ('b, [> read]) t)
    -> ('b, [< _ perms]) t
  val partition_tf
    :  ('a, [> read]) t
    -> f:('a -> bool)
    -> ('a, [< _ perms]) t * ('a, [< _ perms]) t
  val partitioni_tf
    :  ('a, [> read]) t
    -> f:(int -> 'a -> bool)
    -> ('a, [< _ perms]) t * ('a, [< _ perms]) t
  val cartesian_product
    :  ('a, [> read]) t -> ('b, [> read]) t
    -> ('a * 'b, [< _ perms]) t
  val transpose : (('a, [> read]) t, [> read]) t -> (('a, [< _ perms]) t, [< _ perms]) t option
  val transpose_exn : (('a, [> read]) t, [> read]) t -> (('a, [< _ perms]) t, [< _ perms]) t
  val normalize : ('a, _) t -> int -> int
  val slice : ('a, [> read]) t -> int -> int -> ('a, [< _ perms]) t
  val nget : ('a, [> read]) t -> int -> 'a
  val nset : ('a, [> write]) t -> int -> 'a -> unit
  val filter_opt : ('a option, [> read]) t -> ('a, [< _ perms]) t
  val filter_map : ('a, [> read]) t -> f:('a -> 'b option) -> ('b, [< _ perms]) t
  val filter_mapi
    :  ('a, [> read]) t
    -> f:(int -> 'a -> 'b option)
    -> ('b, [< _ perms]) t
  val for_alli :  ('a, [> read]) t -> f:(int -> 'a -> bool) -> bool
  val existsi  :  ('a, [> read]) t -> f:(int -> 'a -> bool) -> bool
  val counti   :  ('a, [> read]) t -> f:(int -> 'a -> bool) -> int
  val iter2_exn : ('a, [> read]) t -> ('b, [> read]) t -> f:('a -> 'b -> unit) -> unit
  val map2_exn
    :  ('a, [> read]) t
    -> ('b, [> read]) t
    -> f:('a -> 'b -> 'c)
    -> ('c, [< _ perms]) t
  val fold2_exn
    :  ('a, [> read]) t
    -> ('b, [> read]) t
    -> init:'c
    -> f:('c -> 'a -> 'b -> 'c)
    -> 'c
  val for_all2_exn
    :  ('a, [> read]) t
    -> ('b, [> read]) t
    -> f:('a -> 'b -> bool)
    -> bool
  val exists2_exn
    :  ('a, [> read]) t
    -> ('b, [> read]) t
    -> f:('a -> 'b -> bool)
    -> bool
  val filter : ('a, [> read]) t -> f:('a -> bool) -> ('a, [< _ perms]) t
  val filteri : ('a, [> read]) t -> f:(int -> 'a -> bool) -> ('a, [< _ perms]) t
  val swap : ('a, [> read_write]) t -> int -> int -> unit
  val rev_inplace : ('a, [> read_write]) t -> unit
  val of_list_rev : 'a list -> ('a, [< _ perms]) t
  val of_list_map : 'a list -> f:('a -> 'b) -> ('b, [< _ perms]) t
  val of_list_rev_map : 'a list -> f:('a -> 'b) -> ('b, [< _ perms]) t
  val replace : ('a, [> read_write]) t -> int -> f:('a -> 'a) -> unit
  val replace_all : ('a, [> read_write]) t -> f:('a -> 'a) -> unit
  [@@deprecated "[since 2018-03] use [map_inplace] instead"]
  val map_inplace : ('a, [> read_write]) t -> f:('a -> 'a) -> unit
  val find_exn : ('a, [> read]) t -> f:('a -> bool) -> 'a
  val find_map_exn : ('a, [> read]) t -> f:('a -> 'b option) -> 'b
  val findi : ('a, [> read]) t -> f:(int -> 'a -> bool) -> (int * 'a) option
  val findi_exn : ('a, [> read]) t -> f:(int -> 'a -> bool) -> int * 'a
  val find_mapi     : ('a, [> read]) t -> f:(int -> 'a -> 'b option) -> 'b option
  val find_mapi_exn : ('a, [> read]) t -> f:(int -> 'a -> 'b option) -> 'b
  val find_consecutive_duplicate
    :  ('a, [> read]) t
    -> equal:('a -> 'a -> bool)
    -> ('a * 'a) option
  val reduce     : ('a, [> read]) t -> f:('a -> 'a -> 'a) -> 'a option
  val reduce_exn : ('a, [> read]) t -> f:('a -> 'a -> 'a) -> 'a
  val permute : ?random_state:Random.State.t -> ('a, [> read_write]) t -> unit
  val random_element : ?random_state:Random.State.t -> ('a, [> read]) t -> 'a option
  val random_element_exn : ?random_state:Random.State.t -> ('a, [> read]) t -> 'a
  val zip     : ('a, [> read]) t -> ('b, [> read]) t -> ('a * 'b, [< _ perms]) t option
  val zip_exn : ('a, [> read]) t -> ('b, [> read]) t -> ('a * 'b, [< _ perms]) t
  val unzip : ('a * 'b, [> read]) t -> ('a, [< _ perms]) t * ('b, [< _ perms]) t
  val sorted_copy : ('a, [> read]) t -> compare:('a -> 'a -> int) -> ('a, [< _ perms]) t
  val last : ('a, [> read]) t -> 'a
  val empty : unit -> ('a, [< _ perms]) t
  [@@deprecated "[since 2017-05] Use [ [||] ]"]
  val equal : ('a, [> read]) t -> ('a, [> read]) t -> equal:('a -> 'a -> bool) -> bool
  val unsafe_truncate : (_, [> write]) t -> len:int -> unit

  val to_sequence : ('a, [> read]) t -> 'a Sequence.t
  val to_sequence_mutable : ('a, [> read]) t -> 'a Sequence.t
end

module Permissioned : sig
  type ('a, -'perms) t [@@deriving bin_io, compare, sexp]

  module Int : sig
    type nonrec -'perms t = (int, 'perms) t [@@deriving bin_io, compare, sexp]

    include Blit.S_permissions with type 'perms t := 'perms t

    external unsafe_blit
      : src:[> read] t -> src_pos:int -> dst:[> write] t -> dst_pos:int -> len:int -> unit
      = "core_array_unsafe_int_blit" [@@noalloc]
  end

  module Float : sig
    type nonrec -'perms t = (float, 'perms) t [@@deriving bin_io, compare, sexp]

    include Blit.S_permissions with type 'perms t := 'perms t

    external unsafe_blit
      : src:[> read] t -> src_pos:int -> dst:[> write] t -> dst_pos:int -> len:int -> unit
      = "core_array_unsafe_float_blit" [@@noalloc]
  end

  val of_array_id : 'a array -> ('a, [< read_write]) t
  val to_array_id : ('a, [> read_write]) t -> 'a array

  val to_sequence_immutable : ('a, [> immutable]) t -> 'a Sequence.t

  include Permissioned with type ('a, 'perms) t := ('a, 'perms) t
end = struct
  type ('a, -'perms) t = 'a array [@@deriving bin_io, compare, sexp, typerep]

  module Int = struct
    include T.Int

    type -'perms t = t_ [@@deriving bin_io, compare, sexp]
  end

  module Float = struct
    include T.Float

    type -'perms t = t_ [@@deriving bin_io, compare, sexp]
  end

  let to_array_id = Fn.id
  let of_array_id = Fn.id

  include (T : Permissioned with type ('a, 'b) t := ('a, 'b) t)
  let to_array = copy
  let to_sequence_immutable = to_sequence_mutable
end

module type S = sig
  type 'a t

  include Binary_searchable.S1 with type 'a t := 'a t
  include Container.S1 with type 'a t := 'a t

  external get : 'a t -> int -> 'a = "%array_safe_get"
  external set : 'a t -> int -> 'a -> unit = "%array_safe_set"
  external unsafe_get : 'a t -> int -> 'a = "%array_unsafe_get"
  external unsafe_set : 'a t -> int -> 'a -> unit = "%array_unsafe_set"

  val create : len:int -> 'a -> 'a t
  val init : int -> f:(int -> 'a) -> 'a t
  val make_matrix : dimx:int -> dimy:int -> 'a -> 'a t t
  val append : 'a t -> 'a t -> 'a t
  val concat : 'a t list -> 'a t
  val copy : 'a t -> 'a t
  val fill : 'a t -> pos:int -> len:int -> 'a -> unit

  include Blit.S1 with type 'a t := 'a t

  val of_list : 'a list -> 'a t
  val map : 'a t -> f:('a -> 'b) -> 'b t
  val folding_map : 'a t -> init:'b -> f:('b -> 'a -> 'b * 'c) -> 'c t
  val fold_map : 'a t -> init:'b -> f:('b -> 'a -> 'b * 'c) -> 'b * 'c t
  val mapi : 'a t -> f:(int -> 'a -> 'b) -> 'b t
  val iteri : 'a t -> f:(int -> 'a -> unit) -> unit
  val foldi : 'a t -> init:'b -> f:(int -> 'b -> 'a -> 'b) -> 'b
  val folding_mapi : 'a t -> init:'b -> f:(int -> 'b -> 'a -> 'b * 'c) -> 'c t
  val fold_mapi : 'a t -> init:'b -> f:(int -> 'b -> 'a -> 'b * 'c) -> 'b * 'c t
  val fold_right : 'a t -> f:('a -> 'b -> 'b) -> init:'b -> 'b
  val sort : ?pos:int -> ?len:int -> 'a t -> compare:('a -> 'a -> int) -> unit
  val stable_sort : 'a t -> compare:('a -> 'a -> int) -> unit
  val is_sorted : 'a t -> compare:('a -> 'a -> int) -> bool
  val is_sorted_strictly : 'a t -> compare:('a -> 'a -> int) -> bool
  val concat_map : 'a t -> f:('a -> 'b t) -> 'b t
  val concat_mapi : 'a t -> f:(int -> 'a -> 'b t) -> 'b t
  val partition_tf : 'a t -> f:('a -> bool) -> 'a t * 'a t
  val partitioni_tf : 'a t -> f:(int -> 'a -> bool) -> 'a t * 'a t
  val cartesian_product : 'a t -> 'b t -> ('a * 'b) t
  val transpose : 'a t t -> 'a t t option
  val transpose_exn : 'a t t -> 'a t t
  val normalize : 'a t -> int -> int
  val slice : 'a t -> int -> int -> 'a t
  val nget : 'a t -> int -> 'a
  val nset : 'a t -> int -> 'a -> unit
  val filter_opt : 'a option t -> 'a t
  val filter_map : 'a t -> f:('a -> 'b option) -> 'b t
  val filter_mapi : 'a t -> f:(int -> 'a -> 'b option) -> 'b t
  val for_alli : 'a t -> f:(int -> 'a -> bool) -> bool
  val existsi  : 'a t -> f:(int -> 'a -> bool) -> bool
  val counti   : 'a t -> f:(int -> 'a -> bool) -> int
  val iter2_exn : 'a t -> 'b t -> f:('a -> 'b -> unit) -> unit
  val map2_exn : 'a t -> 'b t -> f:('a -> 'b -> 'c) -> 'c t
  val fold2_exn : 'a t -> 'b t -> init:'c -> f:('c -> 'a -> 'b -> 'c) -> 'c
  val for_all2_exn : 'a t -> 'b t -> f:('a -> 'b -> bool) -> bool
  val exists2_exn : 'a t -> 'b t -> f:('a -> 'b -> bool) -> bool
  val filter : 'a t -> f:('a -> bool) -> 'a t
  val filteri : 'a t -> f:(int -> 'a -> bool) -> 'a t
  val swap : 'a t -> int -> int -> unit
  val rev_inplace : 'a t -> unit
  val of_list_rev : 'a list -> 'a t
  val of_list_map : 'a list -> f:('a -> 'b) -> 'b t
  val of_list_rev_map : 'a list -> f:('a -> 'b) -> 'b t
  val replace : 'a t -> int -> f:('a -> 'a) -> unit
  val replace_all : 'a t -> f:('a -> 'a) -> unit
  [@@deprecated "[since 2018-03] use [map_inplace] instead"]
  val map_inplace : 'a t -> f:('a -> 'a) -> unit
  val find_exn : 'a t -> f:('a -> bool) -> 'a
  val find_map_exn : 'a t -> f:('a -> 'b option) -> 'b
  val findi : 'a t -> f:(int -> 'a -> bool) -> (int * 'a) option
  val findi_exn : 'a t -> f:(int -> 'a -> bool) -> int * 'a
  val find_mapi : 'a t -> f:(int -> 'a -> 'b option) -> 'b option
  val find_mapi_exn : 'a t -> f:(int -> 'a -> 'b option) -> 'b
  val find_consecutive_duplicate : 'a t -> equal:('a -> 'a -> bool) -> ('a * 'a) option
  val reduce     : 'a t -> f:('a -> 'a -> 'a) -> 'a option
  val reduce_exn : 'a t -> f:('a -> 'a -> 'a) -> 'a
  val permute : ?random_state:Random.State.t -> 'a t -> unit
  val random_element : ?random_state:Random.State.t -> 'a t -> 'a option
  val random_element_exn : ?random_state:Random.State.t -> 'a t -> 'a
  val zip     : 'a t -> 'b t -> ('a * 'b) t option
  val zip_exn : 'a t -> 'b t -> ('a * 'b) t
  val unzip : ('a * 'b) t -> 'a t * 'b t
  val sorted_copy : 'a t -> compare:('a -> 'a -> int) -> 'a t
  val last : 'a t -> 'a
  val empty : unit -> 'a t
  [@@deprecated "[since 2017-05] Use [ [||] ]"]
  val equal : 'a t -> 'a t -> equal:('a -> 'a -> bool) -> bool
  val unsafe_truncate : _ t -> len:int -> unit

  val to_sequence : 'a t -> 'a Core_sequence.t
  val to_sequence_mutable : 'a t -> 'a Core_sequence.t
end

include (T : S with type 'a t := 'a array)

let invariant invariant_a t = iter t ~f:invariant_a

let max_length = Sys.max_array_length

module Int = struct
  include T.Int
  type t = t_ [@@deriving bin_io, compare, sexp]
end

module Float = struct
  include T.Float
  type t = t_ [@@deriving bin_io, compare, sexp]
end

module Check1 (M : S) : sig
  type ('a, -'perm) t_
  include Permissioned with type ('a, 'perm) t := ('a, 'perm) t_
end = struct
  include M
  type ('a, -'perm) t_ = 'a t
end

module Check2 (M : Permissioned) : sig
  type 'a t_
  include S with type 'a t := 'a t_
end = struct
  include M
  type 'a t_ = ('a, read_write) t
end
