(** A simple polymorphic functional queue.  Use this data structure for strictly first-in,
    first-out access to a sequence of values.  For a similar data structure with enqueue
    and dequeue accessors on both ends of a sequence, see
    {{!Core_kernel.Fdeque}[Core_kernel.Fdeque]}.

    Amortized running times assume that [enqueue]/[dequeue] are used sequentially,
    threading the changing Fqueue through the calls. *)

open! Import

type 'a t [@@deriving bin_io, compare, hash, sexp]

include Container.S1 with type 'a t := 'a t
include Invariant.S1 with type 'a t := 'a t
include Monad.S      with type 'a t := 'a t

(** The empty queue. *)
val empty : 'a t

(** [enqueue t x] returns a queue with adds [x] to the end of [t]. Complexity: O(1). *)
val enqueue : 'a t -> 'a -> 'a t


(** Enqueues a single element on the *top* of the queue.  Complexity: amortized O(1)
    [enqueue_top] is deprecated, use [Fdeque.t] instead. *)
val enqueue_top : 'a t -> 'a -> 'a t

(** Returns the bottom (most recently enqueued) element.  Raises [Empty] if no element is
    found.  Complexity: O(1).

    [bot_exn] is deprecated, use [Fdeque.t] instead. *)
val bot_exn : 'a t -> 'a

(** Like [bot_exn], but returns its result optionally, without exception. Complexity:
    O(1).

    [bot] is deprecated, use [Fdeque.t] instead. *)
val bot : 'a t -> 'a option

(** Like [bot_exn], except returns top (least recently enqueued) element. Complexity:
    O(1). *)
val top_exn : 'a t -> 'a

(** Like [top_exn], but returns its result optionally, without exception,
    Complexity: O(1). *)
val top : 'a t -> 'a option

(** [dequeue_exn t] removes and returns the front of [t], raising [Empty] if [t]
    is empty. Complexity: amortized O(1)*)
val dequeue_exn : 'a t -> 'a * 'a t

(** Like [dequeue_exn], but returns result optionally, without exception.  Complexity:
    amortized O(1) *)
val dequeue : 'a t -> ('a * 'a t) option

(** Returns version of queue with top element removed.  Complexity: amortized O(1). *)
val discard_exn : 'a t -> 'a t

(** [to_list t] returns a list of the elements in [t] in order from least-recently-added
    (at the head) to most-recently-added (at the tail). Complexity: O(n). *)
val to_list : 'a t -> 'a list

(** [of_list] is the inverse of [to_list]. Complexity: O(n). *)
val of_list : 'a list -> 'a t

(** Complexity: O(1). *)
val length : 'a t -> int

(** Complexity: O(1). *)
val is_empty : 'a t -> bool

val singleton : 'a -> 'a t

module Stable : sig
  module V1 : Stable_module_types.S1 with type 'a t = 'a t
end
