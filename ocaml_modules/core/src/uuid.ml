(* A loose implementation of version 3 of the UUID spec:

   Version 3 UUIDs use a scheme deriving a UUID via MD5 from a URL, a fully
   qualified domain name, an object identifier, a distinguished name (DN as used
   in Lightweight Directory Access Protocol), or on names in unspecified
   namespaces. Version 3 UUIDs have the form xxxxxxxx-xxxx-3xxx-xxxx-xxxxxxxxxxxx
   with hexadecimal digits x.
*)

module Stable = struct
  open Core_kernel.Core_kernel_stable
  module V1 = struct
    module T = struct
      type t = string [@@deriving bin_io, compare, hash, sexp]
      include (val Comparator.V1.make ~compare ~sexp_of_t)
    end
    include T
    include Comparable.V1.Make (T)

    let for_testing = "5a863fc1-67b7-3a0a-dc90-aca2995afbf9"
  end
end

open! Import
open! Import_time

module Unix = Core_unix

module T = struct
  type t = string [@@deriving bin_io, compare, hash]

  type comparator_witness = Stable.V1.comparator_witness
  let comparator = Stable.V1.comparator

  let next_counter =
    let counter = ref 0 in
    (fun () ->
       (* In OCaml this doesn't allocate, and threads can't context switch except on
          allocation *)
       incr counter;
       !counter)
  ;;

  let gethostname = Memo.unit Unix.gethostname

  (* [create] is responsible for generating unique string identifiers.  It should be clear
     to a reader that the id generated has an extremely high probability of uniqueness
     across all possible machines, processes, and threads of execution. *)

  let create () =
    let digest =
      let hostname = gethostname () in
      let pid      = Unix.getpid () in
      let time     = Time.now () in
      let counter  = next_counter () in
      let base =
        String.concat ~sep:"-"
          [ hostname
          ; Int.to_string (Pid.to_int pid)
          ; Float.to_string_12 (Time.Span.to_sec (Time.to_span_since_epoch time))
          ; Int.to_string counter
          ]
      in
      Md5.to_hex (Md5.digest_string base)
    in
    let s = Bytes.create 36 in
    Bytes.set s 8 '-';
    Bytes.set s 13 '-';
    Bytes.set s 18 '-';
    Bytes.set s 23 '-';
    Bytes.From_string.blit ~src:digest ~dst:s ~src_pos:0 ~dst_pos:0 ~len:8;
    Bytes.From_string.blit ~src:digest ~dst:s ~src_pos:8 ~dst_pos:9 ~len:4;
    Bytes.From_string.blit ~src:digest ~dst:s ~src_pos:12 ~dst_pos:14 ~len:4;
    Bytes.From_string.blit ~src:digest ~dst:s ~src_pos:16 ~dst_pos:19 ~len:4;
    Bytes.From_string.blit ~src:digest ~dst:s ~src_pos:20 ~dst_pos:24 ~len:12;
    Bytes.set s 14 '3';
    Bytes.to_string s
  ;;

  let to_string = ident

  (*{v
     xxxxxxxx-xxxx-3xxx-xxxx-xxxxxxxxxxxx
     012345678901234567890123456789012345
     0         1         2         3
  v}*)

  let char_is_dash c = Char.equal '-' c

  let is_valid_exn s =
    (* we don't check for a 3 in the version position (14) because we want to be
       generous about accepting UUIDs generated by other versions of the protocol, and
       we want to be resilient to future changes in this algorithm. *)
    assert (String.length s = 36);
    assert (String.count s ~f:char_is_dash = 4);
    assert (char_is_dash s.[8]);
    assert (char_is_dash s.[13]);
    assert (char_is_dash s.[18]);
    assert (char_is_dash s.[23]);
  ;;


  let of_string s =
    try
      is_valid_exn s;
      s
    with
    | _ -> failwithf "%s: not a valid UUID" s ()
  ;;

end

include T

include Identifiable.Make_using_comparator (struct
    let module_name = "Core.Uuid"
    include T
    include Sexpable.Of_stringable (T)
  end)

let invariant t = ignore (of_string t : t)

let nil = "00000000-0000-0000-0000-000000000000"

let%test_unit "nil is valid" =
  is_valid_exn nil
;;

module Unstable = struct
  type nonrec t = t [@@deriving bin_io, compare, hash, sexp]
end

let to_string_hum t =
  if am_running_inline_test
  then nil
  else to_string t
;;

let sexp_of_t t =
  if am_running_inline_test
  then sexp_of_t nil
  else sexp_of_t t
;;

module Test = struct
  let test_size = 100_000

  let no_collisions l =
    let rec loop set l =
      match l with
      | []        -> true
      | t :: rest ->
        if Set.mem set t
        then false
        else loop (Set.add set t) rest
    in
    loop Set.empty l
  ;;

  let generate (n:int) =
    let rec loop acc n =
      if Int.(=) n 0 then acc
      else loop (create () :: acc) (n - 1)
    in
    loop [] n
  ;;

  let thread_test () =
    let res1 = ref [] in
    let res2 = ref [] in
    let thread1 = Thread.create (fun () -> res1 := generate test_size) () in
    let thread2 = Thread.create (fun () -> res2 := generate test_size) () in
    Thread.join thread1;
    Thread.join thread2;
    no_collisions (List.rev_append !res1 !res2)
  ;;

  let%test _ = no_collisions (generate test_size)
  let%test _ = thread_test ()

  let%expect_test "UUIDs are shown as [nil] in tests" =
    print_endline (to_string_hum (create ()));
    [%expect {| 00000000-0000-0000-0000-000000000000 |}];
    print_s [%sexp (create () : t)];
    [%expect {| 00000000-0000-0000-0000-000000000000 |}];
  ;;
end
