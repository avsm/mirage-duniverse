open! Core_kernel
open! Expect_test_helpers_kernel
open! List

let print2 x1 x2    = print_s [%message (x1 : int) (x2 : int)]
let print3 x1 x2 x3 = print_s [%message (x1 : int) (x2 : int) (x3 : int)]
let print2_and_return result x1 x2 = print2 x1 x2; result

let test2 list_f f sexp_of_result =
  print_s [%message
    "" ~result:(list_f [ 1    ] [ 2; 3 ] ~f : result Or_unequal_lengths.t)];
  print_s [%message
    "" ~result:(list_f [ 1; 2 ] [ 3; 4 ] ~f : result Or_unequal_lengths.t)];
;;

let test3 list_f f sexp_of_result =
  print_s [%message
    "" ~result:(list_f [ 1    ] [ 2; 3 ] [ 4; 5 ] ~f : result Or_unequal_lengths.t)];
  print_s [%message
    "" ~result:(list_f [ 1; 2 ] [ 3; 4 ] [ 5; 6 ] ~f : result Or_unequal_lengths.t)];
;;

let%expect_test "[exists2]" =
  test2 exists2 (print2_and_return false) [%sexp_of: bool];
  [%expect {|
    (result Unequal_lengths)
    ((x1 1)
     (x2 3))
    ((x1 2)
     (x2 4))
    (result (Ok false)) |}];
  test2 exists2 (print2_and_return true) [%sexp_of: bool];
  [%expect {|
    (result Unequal_lengths)
    ((x1 1)
     (x2 3))
    (result (Ok true)) |}];
;;

let%expect_test "[fold2]" =
  test2 (fold2 ~init:[])
    (fun ac x1 x2 -> print2 x1 x2; (x1, x2) :: ac)
    [%sexp_of: (int * int) list];
  [%expect {|
    (result Unequal_lengths)
    ((x1 1)
     (x2 3))
    ((x1 2)
     (x2 4))
    (result (
      Ok (
        (2 4)
        (1 3)))) |}];
;;

let%expect_test "[for_all2]" =
  test2 for_all2 (print2_and_return false) [%sexp_of: bool];
  [%expect {|
    (result Unequal_lengths)
    ((x1 1)
     (x2 3))
    (result (Ok false)) |}];
  test2 for_all2 (print2_and_return true) [%sexp_of: bool];
  [%expect {|
    (result Unequal_lengths)
    ((x1 1)
     (x2 3))
    ((x1 2)
     (x2 4))
    (result (Ok true)) |}];
;;

let%expect_test "[iter2]" =
  test2 iter2 (print2_and_return ()) [%sexp_of: unit];
  [%expect {|
    (result Unequal_lengths)
    ((x1 1)
     (x2 3))
    ((x1 2)
     (x2 4))
    (result (Ok ())) |}];
;;

let%expect_test "[map2]" =
  test2 map2 (fun x1 x2 -> print2 x1 x2; (x1, x2)) [%sexp_of: (int * int) list];
  [%expect {|
    (result Unequal_lengths)
    ((x1 1)
     (x2 3))
    ((x1 2)
     (x2 4))
    (result (
      Ok (
        (1 3)
        (2 4)))) |}];
;;

let%expect_test "[map3]" =
  test3 map3 (fun x1 x2 x3 -> print3 x1 x2 x3; (x1, x2, x3))
    [%sexp_of: (int * int * int) list];
  [%expect {|
    (result Unequal_lengths)
    ((x1 1)
     (x2 3)
     (x3 5))
    ((x1 2)
     (x2 4)
     (x3 6))
    (result (
      Ok (
        (1 3 5)
        (2 4 6)))) |}];
;;

let%expect_test "[rev_map2]" =
  test2 rev_map2 (fun x1 x2 -> print2 x1 x2; (x1, x2)) [%sexp_of: (int * int) list];
  [%expect {|
    (result Unequal_lengths)
    ((x1 1)
     (x2 3))
    ((x1 2)
     (x2 4))
    (result (
      Ok (
        (2 4)
        (1 3)))) |}];
;;

let%expect_test "[rev_map3]" =
  test3 rev_map3 (fun x1 x2 x3 -> print3 x1 x2 x3; (x1, x2, x3))
    [%sexp_of: (int * int * int) list];
  [%expect {|
    (result Unequal_lengths)
    ((x1 1)
     (x2 3)
     (x3 5))
    ((x1 2)
     (x2 4)
     (x3 6))
    (result (
      Ok (
        (2 4 6)
        (1 3 5)))) |}];
;;
