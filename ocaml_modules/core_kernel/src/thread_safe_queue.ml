(* This module exploits the fact that OCaml does not perform context-switches under
   certain conditions.  It can therefore avoid using mutexes.

   Given the semantics of the current OCaml runtime (and for the foreseeable future), code
   sections documented as atomic below will never contain a context-switch.  The deciding
   criterion is whether they contain allocations or calls to external/builtin functions.
   If there is none, a context-switch cannot happen.  Assignments without allocations,
   field access, pattern-matching, etc., do not trigger context-switches.

   Code reviewers should therefore make sure that the sections documented as atomic below
   do not violate the above assumptions.  It is prudent to disassemble the .o file (using
   [objdump -dr]) and examine it. *)

open! Import

open Std_internal

(* This [Uopt] type is not exposed to users, and is only used as an [Elt.value] field. *)
module Uopt : sig

  type 'a t [@@deriving sexp_of]

  val none : _ t
  val some : 'a -> 'a t
  val is_none : _ t -> bool
  val is_some : _ t -> bool

  val value_exn : 'a t -> 'a

  (* [unsafe_value t] is only safe if [is_some t]. *)
  val unsafe_value : 'a t -> 'a

end = struct

  type 'a t = Obj.t

  let none = Obj.repr "Thread_safe_queue.Uopt.none"

  let is_none t = phys_equal t none

  let is_some t = not (is_none t)

  let some (type a) a = Obj.repr (a : a)

  let%test _ = is_none none

  let%test _ = is_some (some ())

  let unsafe_value (type a) t = (Obj.obj t : a)

  let value_exn t =
    if is_none t then failwith "Uopt.value_exn";
    unsafe_value t
  ;;

  let sexp_of_t sexp_of_a t =
    if is_none t
    then "None" |> [%sexp_of: string]
    else ("Some", unsafe_value t) |> [%sexp_of: string * a]
  ;;
end

module Elt = struct
  type 'a t =
    { mutable value : 'a Uopt.t
    ; mutable next  : 'a t Uopt.t sexp_opaque
    }
  [@@deriving sexp_of]

  let create () = { value = Uopt.none; next = Uopt.none }

end

type 'a t =
  { mutable length          : int
  (* [front] to [back] has [length + 1] linked elements, where the first [length] hold the
     values in the queue, and the last is [back], holding no value. *)
  ; mutable front           : 'a Elt.t
  ; mutable back            : 'a Elt.t
  (* [unused_elts] is singly linked via [next], and ends with [sentinel].  All elts in
     [unused_elts] have [Uopt.is_none elt.value]. *)
  ; mutable unused_elts     : 'a Elt.t Uopt.t
  }
[@@deriving fields, sexp_of]

let invariant _invariant_a t =
  Invariant.invariant [%here] t [%sexp_of: _ t] (fun () ->
    let check f = Invariant.check_field t f in
    Fields.iter
      ~length:(check (fun length ->
        assert (length >= 0)))
      ~front:(check (fun front ->
        let i = ref t.length in
        let r = ref front in
        while !i > 0 do
          decr i;
          let elt = !r in
          r := Uopt.value_exn elt.Elt.next;
          assert (Uopt.is_some elt.value);
        done;
        assert (phys_equal !r t.back)))
      ~back:(check (fun back ->
        assert (Uopt.is_none back.Elt.value)))
      ~unused_elts:(check (fun unused_elts ->
        let r = ref unused_elts in
        while Uopt.is_some !r do
          let elt = Uopt.value_exn !r in
          r := elt.Elt.next;
          assert (Uopt.is_none elt.value);
        done)))
;;

let create () =
  let elt = Elt.create () in
  { front           = elt
  ; back            = elt
  ; length          = 0
  ; unused_elts     = Uopt.none
  }
;;

let get_unused_elt t =
  (* BEGIN ATOMIC SECTION *)
  if Uopt.is_some t.unused_elts
  then begin
    let elt = Uopt.unsafe_value t.unused_elts in
    t.unused_elts <- elt.next;
    elt;
  end
  (* END ATOMIC SECTION *)
  else Elt.create ()
;;

let enqueue (type a) (t : a t) (a : a) =
  let new_back = get_unused_elt t in
  (* BEGIN ATOMIC SECTION *)
  t.length <- t.length + 1;
  t.back.value <- Uopt.some a;
  t.back.next  <- Uopt.some new_back;
  t.back <- new_back;
  (* END ATOMIC SECTION *)
;;

let return_unused_elt t (elt : _ Elt.t) =
  (* BEGIN ATOMIC SECTION *)
  elt.value <- Uopt.none;
  elt.next <- t.unused_elts;
  t.unused_elts <- Uopt.some elt;
  (* END ATOMIC SECTION *)
;;

let [@inline never] raise_dequeue_empty t =
  failwiths "Thread_safe_queue.dequeue_exn of empty queue" t [%sexp_of: _ t]
;;

let dequeue_exn t =
  (* BEGIN ATOMIC SECTION *)
  if t.length = 0 then raise_dequeue_empty t;
  let elt = t.front in
  let a = elt.value in
  t.front <- Uopt.unsafe_value elt.next;
  t.length <- t.length - 1;
  (* END ATOMIC SECTION *)
  return_unused_elt t elt;
  Uopt.unsafe_value a
;;

let clear_internal_pool t = t.unused_elts <- Uopt.none
