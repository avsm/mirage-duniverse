open! Import
open Std_internal
open! Int.Replace_polymorphic_compare

module Stable = struct
  module V1 = struct
    module Parts = struct
      type t = {
        sign : Sign.t;
        hr   : int;
        min  : int;
        sec  : int;
        ms   : int;
        us   : int;
        ns   : int;
      }
      [@@deriving sexp]
    end

    module type Like_a_float = sig
      type t [@@deriving bin_io, hash]

      include Comparable.S_common  with type t := t
      include Comparable.With_zero with type t := t
      include Floatable            with type t := t
      val (+)     : t -> t -> t
      val (-)     : t -> t -> t
      val zero    : t
      val robust_comparison_tolerance : t
      val abs     : t -> t
      val neg     : t -> t
      val scale   : t -> float -> t
    end

    module T : sig
      type underlying = float [@@deriving hash]
      type t = private underlying [@@deriving bin_io, hash]

      include Like_a_float with type t := t
      include Robustly_comparable  with type t := t

      module Constant : sig
        val nanoseconds_per_second : float
        val microseconds_per_second : float
        val milliseconds_per_second : float
        val nanosecond : t
        val microsecond : t
        val millisecond : t
        val second : t
        val minute : t
        val hour : t
        val day : t
      end

      val to_parts : t -> Parts.t

      val next : t -> t
      val prev : t -> t
    end = struct
      type underlying = float [@@deriving hash]
      type t = underlying [@@deriving hash]

      let next t = Float.one_ulp `Up t
      let prev t = Float.one_ulp `Down t

      (* IF THIS REPRESENTATION EVER CHANGES, ENSURE THAT EITHER
         (1) all values serialize the same way in both representations, or
         (2) you add a new Time.Span version to stable.ml *)
      include (struct
        include Float
        let sign = sign_exn
      end : Like_a_float with type t := t)

      (* due to precision limitations in float we can't expect better than microsecond
         precision *)
      include Float.Robust_compare.Make
          (struct let robust_comparison_tolerance = 1E-6 end)

      (* this prevents any worry about having these very common names redefined below and
         makes their usage within this module safer.  Constant is included at the very
         bottom to re-export these constants in a more convenient way *)
      module Constant = struct
        let nanoseconds_per_second = 1E9
        let microseconds_per_second = 1E6
        let milliseconds_per_second = 1E3
        (* spans are stored as a float in seconds *)
        let nanosecond  = of_float (1. /. nanoseconds_per_second)
        let microsecond = of_float (1. /. microseconds_per_second)
        let millisecond = of_float (1. /. milliseconds_per_second)
        let second      = of_float 1.
        let minute      = of_float 60.
        let hour        = of_float (60. *. 60.)
        let day         = of_float (24. *. 60. *. 60.)
      end


      let to_parts t : Parts.t =
        let sign = Float.sign_exn t in
        let t = abs t in
        let integral = Float.round_down t in
        let fractional = t -. integral in
        let seconds = Float.iround_down_exn integral in
        let nanoseconds = Float.iround_nearest_exn (fractional *. 1E9) in
        let seconds, nanoseconds =
          if Int.equal nanoseconds 1_000_000_000
          then Int.succ seconds, 0
          else          seconds, nanoseconds
        in
        let sec = seconds mod 60 in let minutes = seconds / 60 in
        let min = minutes mod 60 in let hr      = minutes / 60 in
        let ns = nanoseconds  mod 1000 in let microseconds  = nanoseconds  / 1000 in
        let us = microseconds mod 1000 in let milliseconds  = microseconds / 1000 in
        let ms = milliseconds in
        { sign; hr; min; sec; ms; us; ns }
    end

    let format_decimal n tenths units =
      assert (tenths >= 0 && tenths < 10);
      if n < 10 && tenths <> 0
      then sprintf "%d.%d%s" n tenths units
      else sprintf "%d%s" n units

    let to_short_string span =
      let open Parts in
      let parts = T.to_parts span in
      let s =
        if parts.hr > 24 then
          format_decimal
            (parts.hr / 24) (Int.of_float (Float.of_int (parts.hr % 24) /. 2.4)) "d"
        else if parts.hr > 0 then format_decimal parts.hr (parts.min / 6) "h"
        else if parts.min > 0 then format_decimal parts.min (parts.sec / 6) "m"
        else if parts.sec > 0 then format_decimal parts.sec (parts.ms / 100) "s"
        else if parts.ms  > 0 then format_decimal parts.ms  (parts.us / 100) "ms"
        else sprintf "%ius" parts.us
      in
      match parts.sign with
      | Neg        -> "-" ^ s
      | Zero | Pos ->       s

    let (/) t f = T.of_float ((t : T.t :> float) /. f)
    let (//) (f:T.t) (t:T.t) = (f :> float) /. (t :> float)

    (* Multiplying by 1E3 is more accurate than division by 1E-3 *)
    let to_ns (x:T.t)  = (x :> float) *. T.Constant.nanoseconds_per_second
    let to_us (x:T.t)  = (x :> float) *. T.Constant.microseconds_per_second
    let to_ms (x:T.t)  = (x :> float) *. T.Constant.milliseconds_per_second
    let to_sec (x:T.t) = (x :> float)
    let to_min x       = x // T.Constant.minute
    let to_hr x        = x // T.Constant.hour
    let to_day x       = x // T.Constant.day

    let to_int63_seconds_round_down_exn x =
      Float.int63_round_down_exn (to_sec x)

    let ( ** ) f (t:T.t) = T.of_float (f *. (t :> float))
    (* Division by 1E3 is more accurate than multiplying by 1E-3 *)
    let of_ns x              = T.of_float (x /. T.Constant.nanoseconds_per_second)
    let of_us x              = T.of_float (x /. T.Constant.microseconds_per_second)
    let of_ms x              = T.of_float (x /. T.Constant.milliseconds_per_second)
    let of_sec x             = T.of_float x
    let of_int_sec x         = of_sec (Float.of_int x)
    let of_int32_seconds sec = of_sec (Int32.to_float sec)
    (* Note that [Int63.to_float] can lose precision, but only on inputs large enough that
       [of_sec] in either the Time_ns or Time_float case would lose precision (or just be
       plain out of bounds) anyway. *)
    let of_int63_seconds sec = of_sec (Int63.to_float sec)
    let of_min x             = x ** T.Constant.minute
    let of_hr x              = x ** T.Constant.hour
    let of_day x             = x ** T.Constant.day

    let randomize (t:T.t) ~percent =
      if Percent.( < ) percent (Percent.of_mult 0.)
      || Percent.( > ) percent (Percent.of_mult 1.0) then
        invalid_argf !"percent must be between 0%% and 100%%, %{Percent} given"
          percent ();
      let t = to_sec t in
      let distance = Random.float (Percent.apply percent t) in
      of_sec (if Random.bool () then t +. distance else t -. distance)
    ;;

    let create
          ?(sign = Sign.Pos)
          ?(day  = 0)
          ?(hr   = 0)
          ?(min  = 0)
          ?(sec  = 0)
          ?(ms   = 0)
          ?(us   = 0)
          ?(ns   = 0)
          () =
      let (+) = T.(+) in
      let t =
        of_day   (Float.of_int day)
        + of_hr  (Float.of_int hr)
        + of_min (Float.of_int min)
        + of_sec (Float.of_int sec)
        + of_ms  (Float.of_int ms)
        + of_us  (Float.of_int us)
        + of_ns  (Float.of_int ns)
      in
      match sign with
      | Neg -> T.(-) T.zero t
      | Pos | Zero -> t

    include T
    include Constant

    (* WARNING: if you are going to change this function in any material way, make sure
       you update Stable appropriately. *)
    let of_string_v1_v2 (s:string) ~is_v2 =
      try
        begin match s with
        | "" -> failwith "empty string"
        | _  ->
          let float n =
            match (String.drop_suffix s n) with
            | "" -> failwith "no number given"
            | s  ->
              let v = Float.of_string s in
              Validate.maybe_raise (Float.validate_ordinary v);
              v
          in
          let len = String.length s in
          match s.[Int.(-) len 1] with
          | 's' ->
            if Int.(>=) len 2 && Char.(=) s.[Int.(-) len 2] 'm'
            then of_ms (float 2)
            else if is_v2 && Int.(>=) len 2 && Char.(=) s.[Int.(-) len 2] 'u'
            then of_us (float 2)
            else if is_v2 && Int.(>=) len 2 && Char.(=) s.[Int.(-) len 2] 'n'
            then of_ns (float 2)
            else T.of_float (float 1)
          | 'm' -> of_min (float 1)
          | 'h' -> of_hr (float 1)
          | 'd' -> of_day (float 1)
          | _ ->
            if is_v2
            then failwith "Time spans must end in ns, us, ms, s, m, h, or d."
            else failwith "Time spans must end in ms, s, m, h, or d."
        end
      with exn ->
        invalid_argf "Span.of_string could not parse '%s': %s" s (Exn.to_string exn) ()

    let of_sexp_error_exn exn sexp =
      of_sexp_error (Exn.to_string exn) sexp

    exception T_of_sexp of Sexp.t * exn [@@deriving sexp]
    exception T_of_sexp_expected_atom_but_got of Sexp.t [@@deriving sexp]

    let t_of_sexp_v1_v2 sexp ~is_v2 =
      match sexp with
      | Sexp.Atom x ->
        begin
          try of_string_v1_v2 x ~is_v2
          with exn -> of_sexp_error_exn (T_of_sexp (sexp, exn)) sexp
        end
      | Sexp.List _ ->
        of_sexp_error_exn (T_of_sexp_expected_atom_but_got sexp) sexp

    let string ~is_v2 suffix float =
      if is_v2
      (* This is the same float-to-string conversion used in [Float.sexp_of_t].  It's like
         [Float.to_string], but may leave off trailing period. *)
      then !Sexplib.Conv.default_string_of_float float ^ suffix
      else sprintf "%g%s" float suffix

    (* WARNING: if you are going to change this function in any material way, make sure
       you update Stable appropriately. *)
    (* I'd like it to be the case that you could never construct an infinite span, but I
       can't think of a good way to enforce it.  So this to_string function can produce
       strings that will raise an exception when they are fed to of_string *)
    let to_string_v1_v2 (t:T.t) ~is_v2 =
      (* this is a sad broken abstraction... *)
      let module C = Float.Class in
      match Float.classify (t :> float) with
      | C.Subnormal
      | C.Zero -> "0s"
      | C.Infinite -> if T.(>) t T.zero then "inf" else "-inf"
      | C.Nan -> "nan"
      | C.Normal ->
        let (<) = T.(<) in
        let abs_t = T.of_float (Float.abs (t :> float)) in
        if is_v2 && abs_t < T.Constant.microsecond then string ~is_v2 "ns" (to_ns t)
        else if is_v2 && abs_t < T.Constant.millisecond then string ~is_v2 "us" (to_us t)
        else if abs_t < T.Constant.second then string ~is_v2 "ms" (to_ms t)
        else if abs_t < T.Constant.minute then string ~is_v2 "s" (to_sec t)
        else if abs_t < T.Constant.hour then string ~is_v2 "m" (to_min t)
        else if abs_t < T.Constant.day then string ~is_v2 "h" (to_hr t)
        else string ~is_v2 "d" (to_day t)

    let sexp_of_t_v1_v2 t ~is_v2 = Sexp.Atom (to_string_v1_v2 t ~is_v2)

    let t_of_sexp sexp = t_of_sexp_v1_v2 sexp ~is_v2:false
    let sexp_of_t t = sexp_of_t_v1_v2 t ~is_v2:false
    let of_string s = of_string_v1_v2 s ~is_v2:false
    let to_string t = to_string_v1_v2 t ~is_v2:false
  end

  module V2 = struct

    include V1

    let t_of_sexp sexp = t_of_sexp_v1_v2 sexp ~is_v2:true
    let sexp_of_t t = sexp_of_t_v1_v2 t ~is_v2:true
    let of_string s = of_string_v1_v2 s ~is_v2:true
    let to_string t = to_string_v1_v2 t ~is_v2:true

  end

  let%test_module "Span.V1" = (module Stable_unit_test.Make (struct
      include V1

      let equal t1 t2 = Int.(=) 0 (compare t1 t2)

      let tests =
        let span = of_sec in
        [ span 99e-12,     "9.9e-08ms", "\018\006\211\115\129\054\219\061";
          span 1.2e-9,     "1.2e-06ms", "\076\206\097\227\167\157\020\062";
          span 0.000001,   "0.001ms",   "\141\237\181\160\247\198\176\062";
          span 0.707,      "707ms",     "\057\180\200\118\190\159\230\063";
          span 42.,        "42s",       "\000\000\000\000\000\000\069\064";
          span 1234.56,    "20.576m",   "\010\215\163\112\061\074\147\064";
          span 39_996.,    "11.11h",    "\000\000\000\000\128\135\227\064";
          span 80000006.4, "925.926d",  "\154\153\153\025\208\018\147\065";
        ]
    end))

  let%test_module "Span.V2" = (module Stable_unit_test.Make (struct
      include V2

      let equal t1 t2 = Int.(=) 0 (compare t1 t2)

      let tests =
        let span = of_sec in
        [ span 99e-12,     "0.098999999999999991ns", "\018\006\211\115\129\054\219\061";
          span 1.2e-9,     "1.2ns",                  "\076\206\097\227\167\157\020\062";
          span 0.000001,   "1us",                    "\141\237\181\160\247\198\176\062";
          span 0.707,      "707ms",                  "\057\180\200\118\190\159\230\063";
          span 42.,        "42s",                    "\000\000\000\000\000\000\069\064";
          span 1234.56,    "20.576m",                "\010\215\163\112\061\074\147\064";
          span 39_996.,    "11.11h",                 "\000\000\000\000\128\135\227\064";
          span 80000006.4, "925.926d",               "\154\153\153\025\208\018\147\065";
        ]
    end))

end
include Stable.V2
let sexp_of_t = Stable.V1.sexp_of_t
let to_string = Stable.V1.to_string

let%test_module "conversion compatibility" =
  (module struct

    let tests =
      let span = of_sec in
      [ span 99e-12
      ; span 1.2e-9
      ; span 0.000001
      ; span 0.707
      ; span 42.
      ; span 1234.56
      ; span 39_996.
      ; span 80000006.4
      ]

    let%test_unit _ =
      List.iter tests ~f:(fun t ->
        begin
          (* Output must match Stable.V1: *)
          [%test_result: Sexp.t] (sexp_of_t t) ~expect:(Stable.V1.sexp_of_t t);
          [%test_result: string] (to_string t) ~expect:(Stable.V1.to_string t);
          (* Stable.V1 must accept output (slightly redundant): *)
          [%test_result: t] (Stable.V1.t_of_sexp (sexp_of_t t)) ~expect:t;
          [%test_result: t] (Stable.V1.of_string (to_string t)) ~expect:t;
          (* Stable.V2 should accept output: *)
          [%test_result: t] (Stable.V2.t_of_sexp (sexp_of_t t)) ~expect:t;
          [%test_result: t] (Stable.V2.of_string (to_string t)) ~expect:t;
          (* Should accept Stable.V1 output: *)
          [%test_result: t] (t_of_sexp (Stable.V1.sexp_of_t t)) ~expect:t;
          [%test_result: t] (of_string (Stable.V1.to_string t)) ~expect:t;
          (* Should accept Stable.V2 output: *)
          [%test_result: t] (t_of_sexp (Stable.V2.sexp_of_t t)) ~expect:t;
          [%test_result: t] (of_string (Stable.V2.to_string t)) ~expect:t;
          (* Must round-trip: *)
          [%test_result: t] (t_of_sexp (sexp_of_t t)) ~expect:t;
          [%test_result: t] (of_string (to_string t)) ~expect:t;
        end)

  end)

let to_proportional_float = to_float

let to_unit_of_time t : Unit_of_time.t =
  let abs_t = abs t in
  if abs_t >= day         then Day         else
  if abs_t >= hour        then Hour        else
  if abs_t >= minute      then Minute      else
  if abs_t >= second      then Second      else
  if abs_t >= millisecond then Millisecond else
  if abs_t >= microsecond then Microsecond else
    Nanosecond

let of_unit_of_time : Unit_of_time.t -> t = function
  | Nanosecond  -> nanosecond
  | Microsecond -> microsecond
  | Millisecond -> millisecond
  | Second      -> second
  | Minute      -> minute
  | Hour        -> hour
  | Day         -> day

let to_string_hum ?(delimiter='_') ?(decimals=3) ?(align_decimal=false) ?unit_of_time t =
  let float, suffix =
    match Option.value unit_of_time ~default:(to_unit_of_time t) with
    | Day         -> to_day t, "d"
    | Hour        -> to_hr  t, "h"
    | Minute      -> to_min t, "m"
    | Second      -> to_sec t, "s"
    | Millisecond -> to_ms  t, "ms"
    | Microsecond -> to_us  t, "us"
    | Nanosecond  -> to_ns  t, "ns"
  in
  let prefix =
    Float.to_string_hum float ~delimiter ~decimals ~strip_zero:(not align_decimal)
  in
  let suffix =
    if align_decimal && Int.(=) (String.length suffix) 1
    then suffix ^ " "
    else suffix
  in
  prefix ^ suffix

let%test_unit "Span.to_string_hum" =
  [%test_result: string] (to_string_hum nanosecond) ~expect:"1ns";
  [%test_result: string] (to_string_hum day) ~expect:"1d";
  [%test_result: string]
    (to_string_hum ~decimals:6                      day)
    ~expect:"1d";
  [%test_result: string]
    (to_string_hum ~decimals:6 ~align_decimal:false day)
    ~expect:"1d";
  [%test_result: string]
    (to_string_hum ~decimals:6 ~align_decimal:true  day)
    ~expect:"1.000000d ";
  [%test_result: string]
    (to_string_hum ~decimals:6 ~align_decimal:true ~unit_of_time:Day
       (hour + minute))
    ~expect:"0.042361d "

include Pretty_printer.Register (struct
    type nonrec t = t
    let to_string = to_string
    let module_name = "Core_kernel.Time.Span"
  end)

include Hashable.Make_binable (struct
    type nonrec t = t [@@deriving bin_io, compare, hash, sexp_of]

    (* Previous versions rendered hash-based containers using float serialization rather
       than time serialization, so when reading hash-based containers in we accept either
       serialization. *)
    let t_of_sexp sexp =
      match Float.t_of_sexp sexp with
      | float       -> of_float float
      | exception _ -> t_of_sexp sexp
  end)

module C = struct
  type t = T.t [@@deriving bin_io]

  type comparator_witness = T.comparator_witness

  let comparator = T.comparator

  (* In 108.06a and earlier, spans in sexps of Maps and Sets were raw floats.  From 108.07
     through 109.13, the output format remained raw as before, but both the raw and pretty
     format were accepted as input.  From 109.14 on, the output format was changed from
     raw to pretty, while continuing to accept both formats.  Once we believe most
     programs are beyond 109.14, we will switch the input format to no longer accept
     raw. *)
  let sexp_of_t = sexp_of_t

  let t_of_sexp sexp =
    match Option.try_with (fun () -> T.of_float (Float.t_of_sexp sexp)) with
    | Some t -> t
    | None -> t_of_sexp sexp
  ;;
end

module Map = Map.Make_binable_using_comparator (C)
module Set = Set.Make_binable_using_comparator (C)

let%test _ =
  Set.equal (Set.of_list [hour])
    (Set.t_of_sexp (Sexp.List [Float.sexp_of_t (to_float hour)]))
;;

(* We should be robustly equal within a microsecond *)
let%test _ = (=.) zero microsecond
let%test _ = not ((=.) zero (of_ns 1001.0))
