open! Import

include Caml.Gc

module Stat = struct
  module T = struct
    type t = Caml.Gc.stat = {
      minor_words : float;
      promoted_words : float;
      major_words : float;
      minor_collections : int;
      major_collections : int;
      heap_words : int;
      heap_chunks : int;
      live_words : int;
      live_blocks : int;
      free_words : int;
      free_blocks : int;
      largest_free : int;
      fragments : int;
      compactions : int;
      top_heap_words : int;
      stack_size : int
    } [@@deriving compare, hash, bin_io, sexp, fields]
  end

  include T
  include Comparable.Make(T)
end

module Control = struct
  module T = struct
    type t = Caml.Gc.control = {
      mutable minor_heap_size : int;
      mutable major_heap_increment : int;
      mutable space_overhead : int;
      mutable verbose : int;
      mutable max_overhead : int;
      mutable stack_limit : int;
      mutable allocation_policy : int;
      window_size : int;
    } [@@deriving compare, bin_io, sexp, fields]
  end

  include T
  include Comparable.Make(T)
end

let tune ?logger ?minor_heap_size ?major_heap_increment ?space_overhead
      ?verbose ?max_overhead ?stack_limit ?allocation_policy
      ?window_size () =
  let old_control_params = get () in
  let f opt to_string field =
    let old_value = Field.get field old_control_params in
    match opt with
    | None -> old_value
    | Some new_value ->
      Option.iter logger ~f:(fun f ->
        Printf.ksprintf f "Gc.Control.%s: %s -> %s"
          (Field.name field) (to_string old_value) (to_string new_value));
      new_value
  in
  let new_control_params =
    Control.Fields.map
      ~minor_heap_size:     (f minor_heap_size      string_of_int)
      ~major_heap_increment:(f major_heap_increment string_of_int)
      ~space_overhead:      (f space_overhead       string_of_int)
      ~verbose:             (f verbose              string_of_int)
      ~max_overhead:        (f max_overhead         string_of_int)
      ~stack_limit:         (f stack_limit          string_of_int)
      ~allocation_policy:   (f allocation_policy    string_of_int)
      ~window_size:         (f window_size          string_of_int)
  in
  set new_control_params
;;

module Allocation_policy = struct
  type t =
    | Next_fit
    | First_fit

  let to_int = function
    | Next_fit  -> 0
    | First_fit -> 1
end

let disable_compaction ?logger ~allocation_policy () =
  let allocation_policy =
    match allocation_policy with
    | `Don't_change  -> None
    | `Set_to policy -> Some (Allocation_policy.to_int policy)
  in
  (* The value 1_000_000, according to
     http://caml.inria.fr/pub/docs/manual-ocaml-4.02/libref/Gc.html
     will disable compactions.
  *)
  tune ?logger ?allocation_policy ~max_overhead:1_000_000 ();
;;

external minor_words : unit -> int = "core_kernel_gc_minor_words"
external major_words : unit -> int = "core_kernel_gc_major_words" [@@noalloc]
external promoted_words : unit -> int = "core_kernel_gc_promoted_words" [@@noalloc]
external minor_collections : unit -> int = "core_kernel_gc_minor_collections" [@@noalloc]
external major_collections : unit -> int = "core_kernel_gc_major_collections" [@@noalloc]
external heap_words : unit -> int = "core_kernel_gc_heap_words" [@@noalloc]
external heap_chunks : unit -> int = "core_kernel_gc_heap_chunks" [@@noalloc]
external compactions : unit -> int = "core_kernel_gc_compactions" [@@noalloc]
external top_heap_words : unit -> int = "core_kernel_gc_top_heap_words" [@@noalloc]

external major_plus_minor_words : unit -> int = "core_kernel_gc_major_plus_minor_words"

let zero = int_of_string "0" (* The compiler won't optimize int_of_string away so it won't
                                perform constant folding below. *)
let rec keep_alive o =
  if zero <> 0 then keep_alive o

let%test_unit _ =
  let r = ref () in
  let weak = Caml.Weak.create 1 in
  Caml.Weak.set weak 0 (Some r);
  Caml.Gc.compact ();
  assert (match Caml.Weak.get weak 0 with None -> false | Some _ -> true);
  keep_alive r
;;

module Expert = struct

  let add_finalizer x f =
    try
      Caml.Gc.finalise
        (fun x -> Exn.handle_uncaught_and_exit (fun () -> f x))
        x
    with Invalid_argument _ ->
      (* The type of add_finalizer ensures that the only possible failure
         is due to [x] being static data. In this case, we simply drop the
         finalizer since static data would never have been collected by the
         GC anyway. *)
      ()
  ;;

  (* [add_finalizer_exn] is the same as [add_finalizer].  However, their types in
     core_gc.mli are different, and the type of [add_finalizer] guarantees that it always
     receives a heap block, which ensures that it will not raise, while
     [add_finalizer_exn] accepts any type, and so may raise. *)
  let add_finalizer_exn x f =
    try
      Caml.Gc.finalise
        (fun x -> Exn.handle_uncaught_and_exit (fun () -> f x))
        x
    with Invalid_argument _ ->
      ignore (Heap_block.create x);
      (* If [Heap_block.create] succeeds then [x] is static data and so
         we can simply drop the finaliser. *)
      ()
  ;;

  let add_finalizer_last x f =
    try
      Caml.Gc.finalise_last
        (fun () -> Exn.handle_uncaught_and_exit f)
        x
    with Invalid_argument _ ->
      (* The type of add_finalizer_last ensures that the only possible failure
         is due to [x] being static data. In this case, we simply drop the
         finalizer since static data would never have been collected by the
         GC anyway. *)
      ()
  ;;

  let add_finalizer_last_exn x f =
    try
      Caml.Gc.finalise_last
        (fun () -> Exn.handle_uncaught_and_exit f)
        x
    with Invalid_argument _ ->
      ignore (Heap_block.create x);
      (* If [Heap_block.create] succeeds then [x] is static data and so
         we can simply drop the finaliser. *)
      ()
  ;;

  let finalize_release = Caml.Gc.finalise_release

  module Alarm = struct
    type t = alarm

    let sexp_of_t _ = "<gc alarm>" |> [%sexp_of: string]

    let create f = create_alarm (fun () -> Exn.handle_uncaught_and_exit f)

    let delete = delete_alarm
  end
end
