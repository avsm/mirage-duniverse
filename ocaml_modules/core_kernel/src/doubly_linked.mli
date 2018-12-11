(** Doubly-linked lists.

    Compared to other doubly-linked lists, in this one:

    1. Calls to modification functions ([insert*], [move*], ...) detect if the list is
    being iterated over ([iter], [fold], ...), and if so raise an exception.  For example,
    a use like the following would raise:

    {[
      iter t ~f:(fun _ -> ... remove t e ...)
    ]}

    2. There is a designated "front" and "back" of each list, rather than viewing each
    element as an equal in a ring.

    3. Elements know which list they're in. Each operation that takes an [Elt.t] also
    takes a [t], first checks that the [Elt] belongs to the [t], and if not, raises.

    4. Related to (3), lists cannot be split, though a sort of splicing is available as
    [transfer]. In other words, no operation will cause one list to become two. This
    makes this module unsuitable for maintaining the faces of a planar graph under edge
    insertion and deletion, for example.

    5. Another property permitted by (3) and (4) is that [length] is O(1).
*)

open! Import

module Elt : sig
  type 'a t

  val value : 'a t -> 'a
  val equal : 'a t -> 'a t -> bool (** pointer equality *)

  val sexp_of_t : ('a -> Base.Sexp.t) -> 'a t -> Base.Sexp.t
end

type 'a t [@@deriving sexp]

include Container.S1 with type 'a t := 'a t
include Invariant.S1 with type 'a t := 'a t

(** {2 Creating doubly-linked lists} *)

val create : unit -> 'a t

(** [of_list l] returns a doubly-linked list [t] with the same elements as [l] and in the
    same order (i.e., the first element of [l] is the first element of [t]). It is always
    the case that [l = to_list (of_list l)]. *)
val of_list : 'a list -> 'a t
val of_array : 'a array -> 'a t

(** {2 Predicates} *)

val equal : 'a t -> 'a t -> bool (** pointer equality *)

val is_first : 'a t -> 'a Elt.t -> bool
val is_last  : 'a t -> 'a Elt.t -> bool
val mem_elt  : 'a t -> 'a Elt.t -> bool

(** {2 Constant-time extraction of first and last elements} *)

val first_elt : 'a t -> 'a Elt.t option
val last_elt : 'a t -> 'a Elt.t option
val first : 'a t -> 'a option
val last : 'a t -> 'a option

(** {2 Constant-time retrieval of next or previous element} *)

val next : 'a t -> 'a Elt.t -> 'a Elt.t option
val prev : 'a t -> 'a Elt.t -> 'a Elt.t option

(** {2 Constant-time insertion of a new element} *)

val insert_before : 'a t -> 'a Elt.t -> 'a -> 'a Elt.t
val insert_after : 'a t -> 'a Elt.t -> 'a -> 'a Elt.t
val insert_first : 'a t -> 'a -> 'a Elt.t
val insert_last : 'a t -> 'a -> 'a Elt.t

(** {2 Constant-time move of an element from and to positions in the same list}

    An exception is raised if [elt] is equal to [anchor]. *)

val move_to_front : 'a t -> 'a Elt.t -> unit
val move_to_back  : 'a t -> 'a Elt.t -> unit
val move_after    : 'a t -> 'a Elt.t -> anchor:'a Elt.t -> unit
val move_before   : 'a t -> 'a Elt.t -> anchor:'a Elt.t -> unit

(** {2 Constant-time removal of an element} *)

val remove : 'a t -> 'a Elt.t -> unit
val remove_first : 'a t -> 'a option
val remove_last : 'a t -> 'a option

(** [fold_elt t ~init ~f] is the same as fold, except [f] is called with the ['a Elt.t]'s
    from the list instead of the contained ['a] values.

    Note that like other iteration functions, it is an error to mutate [t] inside the
    fold. If you'd like to call [remove] on any of the ['a Elt.t]'s, use
    [filter_inplace]. *)
val fold_elt : 'a t -> init:'b -> f:('b -> 'a Elt.t -> 'b) -> 'b

val iter_elt : 'a t -> f:('a Elt.t -> unit) -> unit

val fold_right : 'a t -> init:'b -> f:('a -> 'b -> 'b) -> 'b

(** [find_elt t ~f] finds the first element in [t] that satisfies [f], by testing each of
    element of [t] in turn until [f] succeeds. *)
val find_elt : 'a t -> f:('a -> bool) -> 'a Elt.t option

(** [clear t] removes all elements from the list in constant time. *)
val clear : 'a t -> unit

val copy : 'a t -> 'a t

(** [transfer ~src ~dst] has the same behavior as
    [iter src ~f:(insert_last dst); clear src] except that it runs in constant time.

    If [s = to_list src] and [d = to_list dst], then after [transfer ~src ~dst]:

    [to_list src = []]

    [to_list dst = d @ s] *)
val transfer : src:'a t -> dst:'a t -> unit

(** [filter_inplace t ~f] removes all elements of [t] that don't satisfy [f]. *)
val filter_inplace : 'a t -> f:('a -> bool) -> unit

(** [unchecked_iter t ~f] behaves like [iter t ~f] except that [f] is allowed to modify
    [t]. Adding or removing elements before the element currently being visited has no
    effect on the traversal. Elements added after the element currently being visited
    will be traversed. Elements deleted after the element currently being visited will
    not be traversed. Deleting the element currently being visited is an error that is not
    detected (presumably leading to an infinite loop). *)
val unchecked_iter : 'a t -> f:('a -> unit) -> unit

(** A sequence of values from the doubly-linked list. It makes an intermediate copy of the
    list so that the returned sequence is immune to any subsequent mutation of the
    original list. *)
val to_sequence : 'a t -> 'a Sequence.t
