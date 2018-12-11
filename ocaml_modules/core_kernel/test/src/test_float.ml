open! Core_kernel
open! Import

let%expect_test "[Pervasives.float_of_string] supports underscores" =
  print_endline
    (Pervasives.string_of_float
       (Pervasives.float_of_string "1_234.567_8"));
  [%expect {|
    1234.5678 |}];
;;

let%expect_test "[Sexp.of_float_style] is respected by the various names for [float]" =
  let f = 1234.5678 in
  let print () =
    print_s [%sexp (f : float)];
    print_s [%sexp (f : Float.t)];
    print_s [%sexp (f : Core_kernel.Core_kernel_stable.float)];
  in
  print ();
  [%expect {|
    1234.5678
    1234.5678
    1234.5678 |}];
  Ref.set_temporarily Sexp.of_float_style `Underscores ~f:print;
  [%expect {|
    1_234.5678
    1_234.5678
    1_234.5678 |}];
;;

let%expect_test "[Sexp.of_float_style = `Underscores]" =
  let check f =
    let sexp style =
      Ref.set_temporarily Sexp.of_float_style style ~f:(fun () -> [%sexp (f : float)])
    in
    print_s [%sexp (sexp `No_underscores : Sexp.t),
                   (sexp `Underscores    : Sexp.t)];
    if not (Float.is_nan f)
    then (
      require [%here]
        (Float.equal f (sexp `Underscores |> [%of_sexp: Float.t]))) in
  List.iter
    [ 0.
    ; Float.min_positive_subnormal_value
    ; Float.min_positive_normal_value
    ; 1E-7
    ; 1.
    ; 12.
    ; 123.
    ; 1234.
    ; 12345.
    ; 1234E100
    ; Float.max_value
    ; Float.nan ]
    ~f:(fun f -> check f; check (-. f));
  [%expect {|
    (0 0)
    (-0 -0)
    (4.94065645841247E-324 4.94065645841247E-324)
    (-4.94065645841247E-324 -4.94065645841247E-324)
    (2.2250738585072014E-308 2.2250738585072014E-308)
    (-2.2250738585072014E-308 -2.2250738585072014E-308)
    (1E-07 1E-07)
    (-1E-07 -1E-07)
    (1 1)
    (-1 -1)
    (12 12)
    (-12 -12)
    (123 123)
    (-123 -123)
    (1234 1_234)
    (-1234 -1_234)
    (12345 12_345)
    (-12345 -12_345)
    (1.234E+103 1.234E+103)
    (-1.234E+103 -1.234E+103)
    (INF INF)
    (-INF -INF)
    (NAN NAN)
    ({-,}NAN {-,}NAN) (glob) |}];
;;

let%test_unit "round_nearest_half_to_even quickcheck" =
  Quickcheck.test
    ~trials:200
    (Int.gen_incl (-100_000_000) 100_000_000)
    ~f:(fun i ->
      let x = float i /. 10. in
      let y = Float.round_nearest_half_to_even x in
      let f = Float.round_nearest x in
      let is_tie = Int.(%) i 10 = 5 in
      assert (
        is_tie && Float.mod_float y 2. = 0. && Float.abs (y -. x) = 0.5
        || (not is_tie) && y = f
      );
      let x'  = Float.one_ulp `Up   x in
      let x'' = Float.one_ulp `Down x in
      assert (Float.round_nearest_half_to_even x'  = Float.round_nearest x');
      assert (Float.round_nearest_half_to_even x'' = Float.round_nearest x''))
;;

let%expect_test "robust_sign" =
  let test n = print_s [%sexp (Float.robust_sign n : Sign.t)] in
  test 1e-6;
  [%expect "Pos"];
  test 1e-8;
  [%expect "Zero"];
  test (-1e-6);
  [%expect "Neg"];
  test (-1e-8);
  [%expect "Zero"];
  test (-0.);
  [%expect "Zero"];
  test 0.;
  [%expect "Zero"];
  test Float.neg_infinity;
  [%expect "Neg"];
  (* preserve this old behavior of [sign] *)
  test Float.nan;
  [%expect "Zero"]

(* Make sure float comparison didn't accidentally get redefined using [compare]. *)
let%test _ =
  not (Float.(<) Float.nan 0.)

(* When we put a similar in base/test, it doesn't behave the same, and undesirable
   versions of [Float.is_positive] that allocate when we put the test here don't allocate
   when we put the test there.  So, we put the test here. *)
let%expect_test _ [@tags "64-bits-only", "x-library-inlining-sensitive"] =
  let a = [| 1. |] in (* a.(0) is unboxed *)
  let one = 1. in (* [one] is boxed *)
  ignore (require_no_allocation [%here] (fun () -> Float.(>) a.(0) 0.) : bool);
  [%expect {| |}];
  ignore (require_no_allocation [%here] (fun () -> Float.compare a.(0) 0. > 0) : bool);
  [%expect {| |}];
  ignore (require_no_allocation [%here] (fun () -> Float.is_positive a.(0)) : bool);
  [%expect {| |}];
  ignore (require_no_allocation [%here] (fun () -> Float.is_positive one) : bool);
  [%expect {| |}]

let%test_module "round_significant" =
  (module struct
    let round_significant = Float.round_significant

    let%test_unit "key values" =
      [%test_result: float]
        (round_significant ~significant_digits:3 0.0045678)                ~expect:0.00457;
      [%test_result: float]
        (round_significant ~significant_digits:3 123456.)                  ~expect:123000.;
      [%test_result: float]
        (round_significant ~significant_digits:3 0.)                       ~expect:0.;
      [%test_result: float]
        (round_significant ~significant_digits:3 Float.nan)                ~expect:Float.nan;
      [%test_result: float]
        (round_significant ~significant_digits:3 Float.infinity)           ~expect:Float.infinity;
      [%test_result: float]
        (round_significant ~significant_digits:3 Float.neg_infinity)       ~expect:Float.neg_infinity;
      [%test_result: float]
        (round_significant ~significant_digits:1 (-5.85884163457842E+100)) ~expect:(-6E+100);
      [%test_result: float]
        (round_significant ~significant_digits:16 (-129361178280336660.))  ~expect:(-129361178280336700.);
      (* An example where it appears like we don't round to even (since the argument is
         under-represented as a float). *)
      [%test_result: float]
        (round_significant ~significant_digits:11 4.36083208835)           ~expect:(4.3608320883)
    ;;

    let%test_unit "round_significant vs sprintf quickcheck 1" [@tags "64-bits-only"] =
      for significant_digits = 1 to 16 do
        let open Quickcheck in
        test Float.gen_without_nan
          ~trials:10_000
          ~sexp_of:(fun float -> [%message "" (float : float) (significant_digits : int)])
          ~f:(fun x ->
            let s = sprintf "%.*g" significant_digits x |> Float.of_string in
            assert
              (s = round_significant ~significant_digits x ||
               s = round_significant ~significant_digits (Float.one_ulp `Up x) ||
               s = round_significant ~significant_digits (Float.one_ulp `Down x)))
      done
    ;;

    let%test_unit "round_significant vs sprintf quickcheck 2" [@tags "64-bits-only"] =
      (* this test is much more likely to exercise cases when we're off by an ulp *)
      let num_digits_gen = Int.gen_incl 1 18 in
      let digits_gen num_digits =
        let x = Int63.(pow (of_int 10) (of_int num_digits) - of_int 1) in
        Int63.gen_incl Int63.((~-) x) x
      in
      let scale_gen = Int.gen_incl (-20) 20 in
      let sf_gen    = Int.gen_incl 1     18 in
      Quickcheck.test
        ~trials:1000
        (Quickcheck.Generator.tuple3
           (Quickcheck.Generator.bind num_digits_gen ~f:digits_gen)
           scale_gen
           sf_gen)
        ~f:(fun (digits, scale, sf) ->
          let x =
            if scale > 0 then
              Int63.to_float digits *. (10. ** float scale)
            else
              Int63.to_float digits /. (10. ** float (-scale))
          in
          let r  = round_significant ~significant_digits:sf x in
          let r1 = round_significant ~significant_digits:sf (Float.one_ulp `Up x) in
          let r2 = round_significant ~significant_digits:sf (Float.one_ulp `Down x) in
          let s = sprintf "%.*g" sf x |> Float.of_string in
          assert (s = r || s = r1 || s = r2))
    ;;

    let%test "0 significant digits" =
      Exn.does_raise (fun () -> ignore (round_significant ~significant_digits:0 1.3 : float))
    ;;
  end)

let%test_module "round_decimal" =
  (module struct
    let round_decimal = Float.round_decimal

    let%test_unit "key values" =
      [%test_result: float]
        (round_decimal ~decimal_digits:3 0.0045678)                     ~expect:0.005;
      [%test_result: float]
        (round_decimal ~decimal_digits:0 0.0045678)                     ~expect:0.;
      [%test_result: float]
        (round_decimal ~decimal_digits:0 1.0045678)                     ~expect:1.;
      [%test_result: float]
        (round_decimal ~decimal_digits:3 123456.)                       ~expect:123456.;
      [%test_result: float]
        (round_decimal ~decimal_digits:(-3) 123456.)                    ~expect:123000.;
      [%test_result: float]
        (round_decimal ~decimal_digits:3 0.)                            ~expect:0.;
      [%test_result: float]
        (round_decimal ~decimal_digits:3 Float.nan)                     ~expect:Float.nan;
      [%test_result: float]
        (round_decimal ~decimal_digits:3 Float.infinity)                ~expect:Float.infinity;
      [%test_result: float]
        (round_decimal ~decimal_digits:3 Float.neg_infinity)            ~expect:Float.neg_infinity;
      [%test_result: float]
        (round_decimal ~decimal_digits:(-100) (-5.85884163457842E+100)) ~expect:(-6E+100);
      [%test_result: float]
        (round_decimal ~decimal_digits:0 (-129361178280336660.))        ~expect:(-129361178280336660.);
      [%test_result: float]
        (round_decimal ~decimal_digits:(-2) (-129361178280336660.))     ~expect:(-129361178280336700.);
      [%test_result: float]
        (round_decimal ~decimal_digits:10 4.36083208835)                ~expect:(4.3608320883)
    ;;

    let%test_unit "round_decimal vs sprintf quickcheck 1" [@tags "64-bits-only"] =
      for decimal_digits = 1 to 16 do
        let open Quickcheck in
        test Float.gen_without_nan
          ~trials:10_000
          ~sexp_of:(fun float -> [%message "" (float : float) (decimal_digits : int)])
          ~f:(fun x ->
            let s = sprintf "%.*f" decimal_digits x |> Float.of_string in
            assert
              (s = round_decimal ~decimal_digits x ||
               s = round_decimal ~decimal_digits (Float.one_ulp `Up x) ||
               s = round_decimal ~decimal_digits (Float.one_ulp `Down x)))
      done
    ;;
  end)
