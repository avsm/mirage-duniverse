(** A hash-queue is a combination of a queue and a hashtable that
    supports constant-time lookup and removal of queue elements in addition to
    the usual queue operations (enqueue, dequeue). The queue elements are
    key-value pairs. The hashtable has one entry for each element of the queue.

    Calls to functions that would modify a hash-queue (e.g. [enqueue], [dequeue],
    [remove], [replace]) detect if a client is in the middle of iterating over the
    queue (e.g., [iter], [fold], [for_all], [exists]) and if so, raise an exception.
*)

open! Import

(** The key is used for the hashtable of queue elements. *)
module type Key = Hashtbl.Key_plain

module type S = sig
  module Key : Key

  (** A hash-queue, where the values are of type ['a]. *)
  type 'a t [@@deriving sexp_of]

  include Container.S1 with type 'a t := 'a t

  (** [invariant t] checks the invariants of the queue. *)

  val invariant : 'a t -> unit

  (** [create ()] returns an empty queue.  The arguments [growth_allowed] and [size] are
      referring to the underlying hashtable.

      @param growth_allowed defaults to true
      @param size initial size -- default to 16
  *)
  val create
    :  ?growth_allowed:bool
    -> ?size:int
    -> unit
    -> 'a t

  (** Clears the queue. *)
  val clear : 'a t -> unit

  (** {2 Finding elements} *)

  (** [mem q k] returns true iff there is some (k, v) in the queue. *)
  val mem : 'a t -> Key.t -> bool

  (** [lookup t k] returns the value of the key-value pair in the queue with
      key k, if there is one. *)
  val lookup : 'a t -> Key.t -> 'a option

  val lookup_exn : 'a t -> Key.t -> 'a

  (** {2 Adding, removing, and replacing elements}

      Note that even the non-[*_exn] versions can raise, but only if there is an ongoing
      iteration. *)

  (** [enqueue t k v] adds the key-value pair (k, v) to the end of the queue, returning
      [`Ok] if the pair was added, or [`Key_already_present] if there is already a (k, v')
      in the queue.
  *)
  val enqueue : 'a t -> Key.t -> 'a -> [ `Ok | `Key_already_present ]

  val enqueue_exn : 'a t -> Key.t -> 'a -> unit

  val lookup_and_move_to_back     : 'a t -> Key.t -> 'a option

  val lookup_and_move_to_back_exn : 'a t -> Key.t -> 'a

  (** [first t] returns the front element of the queue, without removing it. *)
  val first : 'a t -> 'a option

  (** [first_with_key t] returns the front element of the queue and its key, without
      removing it. *)
  val first_with_key : 'a t -> (Key.t * 'a) option

  (** [keys t] returns the keys in the order of the queue. *)
  val keys : 'a t -> Key.t list

  (** [dequeue t] returns the front element of the queue. *)
  val dequeue : 'a t -> 'a option

  val dequeue_exn : 'a t -> 'a

  (** [dequeue_with_key t] returns the front element of the queue and its key. *)
  val dequeue_with_key : 'a t -> (Key.t * 'a) option

  val dequeue_with_key_exn : 'a t -> (Key.t * 'a)

  (** [dequeue_all t ~f] dequeues every element of the queue and applies [f] to each one. *)
  val dequeue_all : 'a t -> f:('a -> unit) -> unit

  (** [remove q k] removes the key-value pair with key [k] from the queue. *)
  val remove : 'a t -> Key.t -> [ `Ok | `No_such_key ]

  val remove_exn : 'a t -> Key.t -> unit


  (** [replace q k v] changes the value of key [k] in the queue to [v]. *)
  val replace : 'a t -> Key.t -> 'a -> [ `Ok | `No_such_key ]

  val replace_exn : 'a t -> Key.t -> 'a -> unit

  (** {2 Iterating over elements} *)

  (** [iter t ~f] applies [f] to each key and element of the queue. *)
  val iteri : 'a t -> f:(key:Key.t -> data:'a -> unit) -> unit
  val foldi : 'a t -> init:'b -> f:('b -> key:Key.t -> data:'a -> 'b) -> 'b
end

module Make (Key : Key) : S with module Key = Key = struct
  module Key = Key
  module Table = Hashtbl.Make_plain (Key)

  module Key_value = struct
    module T = struct
      type 'a t = {
        key : Key.t;
        mutable value : 'a;
      }
    end
    include T

    let key t = t.key
    let value t = t.value

    let sexp_of_t sexp_of_a {key; value} = [%sexp_of: Key.t * a] (key, value)
  end

  open Key_value.T

  module Elt = Doubly_linked.Elt

  type 'a t = {
    mutable num_readers : int;
    queue : 'a Key_value.t Doubly_linked.t;
    table : 'a Key_value.t Elt.t Table.t;
  }

  let sexp_of_t sexp_of_a t = [%sexp_of: a Key_value.t Doubly_linked.t] t.queue

  let invariant t =
    assert (Doubly_linked.length t.queue = Hashtbl.length t.table);
    (* Look at each element in the queue, checking:
     *   - every element in the queue is in the hash table
     *   - there are no duplicate keys
    *)
    let keys = Table.create ~size:(Hashtbl.length t.table) () in
    Doubly_linked.iter t.queue ~f:(fun kv ->
      let key = kv.key in
      match Hashtbl.find t.table key with
      | None -> assert false
      | Some _ ->
        assert (not (Hashtbl.mem keys key));
        Hashtbl.set keys ~key ~data:());
  ;;

  let create ?(growth_allowed=true) ?(size=16) () = {
    num_readers = 0;
    queue = Doubly_linked.create ();
    table = Table.create ~growth_allowed ~size ();
  }
  ;;

  let read t f =
    t.num_readers <- t.num_readers + 1;
    Exn.protect ~f ~finally:(fun () -> t.num_readers <- t.num_readers - 1)
  ;;

  let ensure_can_modify t =
    if t.num_readers > 0 then
      failwith "It is an error to modify a Hash_queue.t while iterating over it.";
  ;;

  let clear t =
    ensure_can_modify t;
    Doubly_linked.clear t.queue;
    Hashtbl.clear t.table;
  ;;

  let length t = Hashtbl.length t.table

  let is_empty t = length t = 0

  let lookup t k =
    match Hashtbl.find t.table k with
    | None -> None
    | Some elt -> Some (Elt.value elt).value
  ;;

  let lookup_exn t k = (Elt.value (Hashtbl.find_exn t.table k)).value

  let mem t k = Hashtbl.mem t.table k

  (* Note that this is the tail-recursive Core_list.map *)
  let to_list t = List.map (Doubly_linked.to_list t.queue) ~f:Key_value.value

  let to_array t = Array.map (Doubly_linked.to_array t.queue) ~f:Key_value.value

  let for_all t ~f =
    read t (fun () -> Doubly_linked.for_all t.queue ~f:(fun kv -> f kv.value))
  ;;

  let exists t ~f =
    read t (fun () -> Doubly_linked.exists t.queue ~f:(fun kv -> f kv.value))

  let find_map t ~f =
    read t (fun () -> Doubly_linked.find_map t.queue ~f:(fun kv -> f kv.value))
  ;;

  let find t ~f =
    read t (fun () ->
      Option.map (Doubly_linked.find t.queue ~f:(fun kv -> f kv.value))
        ~f:Key_value.value)
  ;;

  let enqueue t key value =
    ensure_can_modify t;
    if Hashtbl.mem t.table key then
      `Key_already_present
    else begin
      let elt =
        Doubly_linked.insert_last t.queue
          { Key_value.key = key; value = value; }
      in
      Hashtbl.set t.table ~key ~data:elt;
      `Ok
    end
  ;;

  exception Enqueue_duplicate_key of Key.t [@@deriving sexp]

  let enqueue_exn t key value =
    match enqueue t key value with
    | `Key_already_present -> raise (Enqueue_duplicate_key key)
    | `Ok -> ()
  ;;

  (* Performance hack: we implement this version separately to avoid allocation from the
     option. *)
  let lookup_and_move_to_back_exn t key =
    ensure_can_modify t;
    let elt = Hashtbl.find_exn t.table key in
    Doubly_linked.move_to_back t.queue elt;
    Key_value.value (Elt.value elt)
  ;;

  let lookup_and_move_to_back t key =
    let open Option.Let_syntax in
    ensure_can_modify t;
    let%map elt = Hashtbl.find t.table key in
    Doubly_linked.move_to_back t.queue elt;
    Key_value.value (Elt.value elt)
  ;;

  let dequeue_with_key t =
    ensure_can_modify t;
    match Doubly_linked.remove_first t.queue with
    | None -> None
    | Some kv -> Hashtbl.remove t.table kv.key; Some (kv.key, kv.value)
  ;;

  exception Deque_with_key_empty [@@deriving sexp]

  let dequeue_with_key_exn t =
    match dequeue_with_key t with
    | None -> raise Deque_with_key_empty
    | Some (k, v) -> (k, v)
  ;;

  let dequeue t =
    match dequeue_with_key t with
    | None -> None
    | Some (_, v) -> Some v
  ;;

  let first_with_key t =
    match Doubly_linked.first t.queue with
    | None -> None
    | Some { key; value; } -> Some (key, value)
  ;;

  let first t =
    match Doubly_linked.first t.queue with
    | None -> None
    | Some kv -> Some kv.value
  ;;

  exception Deque_empty [@@deriving sexp]

  let dequeue_exn t =
    match dequeue t with
    | None -> raise Deque_empty
    | Some v -> v
  ;;

  let keys t =
    (* Return the keys in the order of the queue. *)
    List.map (Doubly_linked.to_list t.queue) ~f:Key_value.key
  ;;

  let iteri t ~f =
    read t (fun () ->
      Doubly_linked.iter t.queue ~f:(fun kv -> f ~key:kv.key ~data:kv.value))
  ;;

  let iter t ~f = iteri t ~f:(fun ~key:_ ~data -> f data)

  let foldi t ~init ~f =
    read t (fun () ->
      Doubly_linked.fold t.queue ~init ~f:(fun ac kv ->
        (f ac ~key:kv.key ~data:kv.value)))
  ;;

  let fold t ~init ~f = foldi t ~init ~f:(fun ac ~key:_ ~data -> f ac data)

  let count t ~f = Container.count ~fold t ~f
  let sum m t ~f = Container.sum m ~fold t ~f
  let min_elt t ~compare = Container.min_elt ~fold t ~compare
  let max_elt t ~compare = Container.max_elt ~fold t ~compare
  let fold_result t ~init ~f = Container.fold_result ~fold ~init ~f t
  let fold_until  t ~init ~f = Container.fold_until  ~fold ~init ~f t

  let dequeue_all t ~f =
    let rec loop () =
      match dequeue t with
      | None -> ()
      | Some v -> f v; loop ()
    in
    loop ()

  let remove t k =
    ensure_can_modify t;
    match Hashtbl.find t.table k with
    | None -> `No_such_key
    | Some elt ->
      Doubly_linked.remove t.queue elt;
      Hashtbl.remove t.table (Elt.value elt).key;
      `Ok
  ;;

  exception Remove_unknown_key of Key.t [@@deriving sexp]

  let remove_exn t k =
    ensure_can_modify t;
    match remove t k with
    | `No_such_key -> raise (Remove_unknown_key k)
    | `Ok -> ()
  ;;

  let replace t k v =
    ensure_can_modify t;
    match Hashtbl.find t.table k with
    | None -> `No_such_key
    | Some elt ->
      (Elt.value elt).value <- v;
      `Ok
  ;;

  exception Replace_unknown_key of Key.t [@@deriving sexp]

  let replace_exn t k v =
    ensure_can_modify t;
    match replace t k v with
    | `No_such_key -> raise (Replace_unknown_key k)
    | `Ok -> ()

end
