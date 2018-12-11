open! Import
open Std_internal

open Digit_string_helpers

let is_leap_year ~year =
  (year mod 4 = 0 && not (year mod 100 = 0))
  || year mod 400 = 0
;;

(* Create a local private date type to ensure that all dates are created via
   Date.create_exn.
*)
module Stable = struct
  module V1 = struct
    module Without_comparable = struct
      module T : sig
        type t [@@deriving bin_io, hash]

        val create_exn : y:int -> m:Month.Stable.V1.t -> d:int -> t

        val year  : t -> int
        val month : t -> Month.Stable.V1.t
        val day   : t -> int
      end = struct
        (* We used to store dates like this:
           type t = { y: int; m: Month.Stable.V1.t; d: int; }
           In the below we make sure that the bin_io representation is
           identical (and the stable unit tests check this)

           In memory we use the following much more compact representation:
           2 bytes year
           1 byte month
           1 byte day

           all packed into a single immediate int (so from 4 words down to 1).
        *)
        type t = int
        [@@deriving hash, bin_shape ~basetype:"899ee3e0-490a-11e6-a10a-a3734f733566"]

        let create0 ~year ~month ~day =
          (* create_exn's validation make sure that each value fits *)
          (year lsl 16) lor (Month.to_int month lsl 8) lor day
        ;;

        let year t = t lsr 16
        let month t = Month.of_int_exn ((t lsr 8) land 0xff)
        let day t = t land 0xff

        let create_exn ~y:year ~m:month ~d:day =
          (* year, month, and day need to be passed as parameters to avoid allocating
             a closure (see unit test below) *)
          let invalid ~year ~month ~day msg =
            invalid_argf "Date.create_exn ~y:%d ~m:%s ~d:%d error: %s"
              year (Month.to_string month) day msg ()
          in
          if year < 0 || year > 9999 then invalid ~year ~month ~day "year outside of [0..9999]";
          if day <= 0 then invalid ~year ~month ~day "day <= 0";
          begin match month with
          | Month.Apr | Month.Jun | Month.Sep | Month.Nov ->
            if day > 30 then invalid ~year ~month ~day "30 day month violation"
          | Month.Feb ->
            if is_leap_year ~year then begin
              if day > 29 then invalid ~year ~month ~day "29 day month violation" else ()
            end else if day > 28 then begin
              invalid ~year ~month ~day "28 day month violation"
            end else ()
          | Month.Jan | Month.Mar | Month.May | Month.Jul | Month.Aug | Month.Oct
          | Month.Dec ->
            if day > 31 then invalid ~year ~month ~day "31 day month violation"
          end;
          create0 ~year ~month:month ~day
        ;;

        (* We don't use Make_binable here, because that would go via an immediate
           tuple or record.  That is exactly the 32 bytes we worked so hard above to
           get rid of.  We also don't want to just bin_io the integer directly
           because that would mean a new bin_io format.  *)

        let bin_read_t buf ~pos_ref =
          let year  = Int.bin_read_t buf ~pos_ref in
          let month = Month.Stable.V1.bin_read_t buf ~pos_ref in
          let day   = Int.bin_read_t buf ~pos_ref in
          create0 ~year ~month ~day
        ;;

        let __bin_read_t__ _buf ~pos_ref =
          (* __bin_read_t is only needed for variants *)
          Bin_prot.Common.raise_variant_wrong_type "Date.t" !pos_ref
        ;;

        let bin_reader_t = {
          Bin_prot.Type_class.
          read = bin_read_t;
          vtag_read = __bin_read_t__;
        }

        let bin_size_t t =
          Int.bin_size_t (year t) + Month.bin_size_t (month t) + Int.bin_size_t (day t)
        ;;

        let bin_write_t buf ~pos t =
          let pos = Int.bin_write_t buf ~pos (year t) in
          let pos = Month.bin_write_t buf ~pos (month t) in
          Int.bin_write_t buf ~pos (day t)
        ;;

        let bin_writer_t = {
          Bin_prot.Type_class.
          size   = bin_size_t;
          write  = bin_write_t;
        }

        let bin_t = {
          Bin_prot.Type_class.
          reader = bin_reader_t;
          writer = bin_writer_t;
          shape = bin_shape_t;
        }
      end

      include T

      (** YYYY-MM-DD *)
      let to_string_iso8601_extended t =
        let buf = Bytes.create 10 in
        write_4_digit_int buf ~pos:0 (year t);
        Bytes.set buf 4 '-';
        write_2_digit_int buf ~pos:5 (Month.to_int (month t));
        Bytes.set buf 7 '-';
        write_2_digit_int buf ~pos:8 (day t);
        Bytes.unsafe_to_string ~no_mutation_while_string_reachable:buf
      ;;

      let to_string = to_string_iso8601_extended

      (** YYYYMMDD *)
      let to_string_iso8601_basic t =
        let buf = Bytes.create 8 in
        write_4_digit_int buf ~pos:0 (year t);
        write_2_digit_int buf ~pos:4 (Month.to_int (month t));
        write_2_digit_int buf ~pos:6 (day t);
        Bytes.unsafe_to_string ~no_mutation_while_string_reachable:buf
      ;;

      (** MM/DD/YYYY *)
      let to_string_american t =
        let buf = Bytes.create 10 in
        write_2_digit_int buf ~pos:0 (Month.to_int (month t));
        Bytes.set buf 2 '/';
        write_2_digit_int buf ~pos:3 (day t);
        Bytes.set buf 5 '/';
        write_4_digit_int buf ~pos:6 (year t);
        Bytes.unsafe_to_string ~no_mutation_while_string_reachable:buf
      ;;

      let parse_year4 str pos = read_4_digit_int str ~pos

      let parse_month str pos = Month.of_int_exn (read_2_digit_int str ~pos)

      let parse_day str pos = read_2_digit_int str ~pos

      (** YYYYMMDD *)
      let of_string_iso8601_basic str ~pos =
        if pos + 8 > String.length str then
          invalid_arg "Date.of_string_iso8601_basic: pos + 8 > string length";
        create_exn
          ~y:(parse_year4 str pos)
          ~m:(parse_month str (pos + 4))
          ~d:(parse_day str (pos + 6))
      ;;

      (* WARNING: if you are going to change this function in a material way, be sure you
         understand the implications of working in Stable *)
      let of_string s =
        let invalid () = failwith ("invalid date: " ^ s) in
        let ensure b = if not b then invalid () in
        let month_num ~year ~month ~day =
          create_exn
            ~y:(parse_year4 s year)
            ~m:(parse_month s month)
            ~d:(parse_day s day)
        in
        let month_abrv ~year ~month ~day =
          create_exn
            ~y:(parse_year4 s year)
            ~m:(Month.of_string (String.sub s ~pos:month ~len:3))
            ~d:(parse_day s day)
        in
        if String.contains s '/' then begin
          let y,m,d =
            match String.split s ~on:'/' with
            | [a; b; c] ->
              if String.length a = 4 then a,b,c (* y/m/d *)
              else c,a,b (* m/d/y *)
            | _ -> invalid ()
          in
          let year = Int.of_string y in
          let year =
            if year >= 100 then year
            else if year < 75 then 2000 + year
            else 1900 + year
          in
          let month = Month.of_int_exn (Int.of_string m) in
          let day = Int.of_string d in
          create_exn ~y:year ~m:month ~d:day
        end else if String.contains s '-' then begin
          (* yyyy-mm-dd *)
          ensure (String.length s = 10 && s.[4] = '-' && s.[7] = '-');
          month_num ~year:0 ~month:5 ~day:8;
        end else if String.contains s ' ' then begin
          if (String.length s = 11 && s.[2] = ' ' && s.[6] = ' ') then
            (* DD MMM YYYY *)
            month_abrv ~day:0 ~month:3 ~year:7
          else begin
            (* YYYY MMM DD *)
            ensure (String.length s = 11 && s.[4] = ' ' && s.[8] = ' ');
            month_abrv ~day:9 ~month:5 ~year:0;
          end
        end else if String.length s = 9 then begin
          (* DDMMMYYYY *)
          month_abrv ~day:0 ~month:2 ~year:5;
        end else if String.length s = 8 then begin
          (* assume YYYYMMDD *)
          month_num ~year:0 ~month:4 ~day:6
        end else invalid ()
      ;;

      let of_string s =
        try of_string s with
        | exn -> invalid_argf "Date.of_string (%s): %s" s (Exn.to_string exn) ()
      ;;

      module Sexpable = struct

        module Old_date = struct
          type t = { y: int; m: int; d: int; } [@@deriving sexp]

          let to_date t = T.create_exn ~y:t.y ~m:(Month.of_int_exn t.m) ~d:t.d
        end

        let t_of_sexp = function
          | Sexp.Atom s -> of_string s
          | Sexp.List _ as sexp -> Old_date.to_date (Old_date.t_of_sexp sexp)
        ;;

        let t_of_sexp s =
          try
            t_of_sexp s
          with
          | (Of_sexp_error _) as exn -> raise exn
          | Invalid_argument a -> of_sexp_error a s
        ;;

        let sexp_of_t t = Sexp.Atom (to_string t)
      end
      include Sexpable

      let compare t1 t2 =
        let n = Int.compare (year t1) (year t2) in
        if n <> 0 then n
        else
          let n = Month.compare (month t1) (month t2) in
          if n <> 0 then n
          else Int.compare (day t1) (day t2)
      ;;

      include (val Comparator.Stable.V1.make ~compare ~sexp_of_t)
    end

    include Without_comparable
    include Comparable.Stable.V1.Make (Without_comparable)
  end
end

module Without_comparable = Stable.V1.Without_comparable

include Without_comparable

module C = Comparable.Make_binable_using_comparator (Without_comparable)

include C
module O = struct
  include (C : Comparable.Infix with type t := t)
end

include (Hashable.Make_binable (struct
           include T
           include Sexpable
           include Binable
           let compare (a:t) (b:t) = compare a b
         end) : Hashable.S_binable with type t := t)

include Pretty_printer.Register (struct
    type nonrec t = t
    let module_name = "Core_kernel.Date"
    let to_string = to_string
  end)

let unix_epoch = create_exn ~y:1970 ~m:Jan ~d:1

(* The Days module is used for calculations that involve adding or removing a known number
   of days from a date.  Internally the date is translated to a day number, the days are
   added, and the new date is returned.  Those interested in the math can read:

   http://alcor.concordia.ca/~gpkatch/gdate-method.html

   note: unit tests are in lib_test/time_test.ml
*)
module Days : sig
  type date = t
  type t

  val of_date : date -> t
  val to_date : t -> date

  val diff     : t -> t -> int
  val add_days : t -> int -> t

  val unix_epoch : t
end with type date := t = struct
  open Int

  type t = int

  let of_year y =
    365 * y + y / 4 - y / 100 + y / 400

  let of_date date =
    let m = (Month.to_int (month date) + 9) % 12 in
    let y = (year date) - m / 10 in
    of_year y + (m * 306 + 5) / 10 + ((day date) - 1)
  ;;

  let c_10_000    = Int63.of_int 10_000
  let c_14_780    = Int63.of_int 14_780
  let c_3_652_425 = Int63.of_int 3_652_425
  let to_date days =
    let y =
      let open Int63 in
      to_int_exn ((c_10_000 * of_int days + c_14_780) / c_3_652_425)
    in
    let ddd = days - of_year y in
    let y, ddd =
      if (ddd < 0)
      then
        let y = y - 1 in
        (y, days - of_year y)
      else (y, ddd)
    in
    let mi = (100 * ddd + 52) / 3_060 in
    let y = y + (mi + 2) / 12 in
    let m = (mi + 2) % 12 + 1 in
    let d = ddd - (mi * 306 + 5) / 10 + 1 in
    create_exn ~y ~m:(Month.of_int_exn m) ~d
  ;;

  let unix_epoch = of_date unix_epoch

  let add_days t days = t + days

  let diff t1 t2 = t1 - t2
end
let add_days t days = Days.to_date (Days.add_days (Days.of_date t) days)
let diff t1 t2 = Days.diff (Days.of_date t1) (Days.of_date t2)

let add_months t n =
  let total_months = (Month.to_int (month t)) + n in
  let y = (year t) + (total_months /% 12) in
  let m = total_months % 12 in
  (* correct for december *)
  let (y, m) =
    if Int.(=) m 0 then
      (y - 1, m + 12)
    else
      (y, m)
  in
  let m = Month.of_int_exn m in
  (* handle invalid dates for months with fewer number of days *)
  let rec try_create d =
    try create_exn ~y ~m ~d
    with _exn ->
      assert (Int.(>=) d 1);
      try_create (d - 1)
  in
  try_create (day t)
;;

let add_years t n =
  add_months t (n * 12)
;;

(* http://en.wikipedia.org/wiki/Determination_of_the_day_of_the_week#Purely_mathematical_methods

   note: unit tests in lib_test/time_test.ml
*)
let day_of_week  =
  let table = [| 0; 3; 2; 5; 0; 3; 5; 1; 4; 6; 2; 4 |] in
  (fun t ->
     let m = Month.to_int (month t) in
     let y = if Int.(<) m 3 then (year t) - 1 else (year t) in
     Day_of_week.of_int_exn ((y + y / 4 - y / 100 + y / 400 + table.(m - 1) + (day t)) % 7))
;;

(* http://en.wikipedia.org/wiki/Ordinal_date *)
let non_leap_year_table = [| 0; 31; 59; 90; 120; 151; 181; 212; 243; 273; 304; 334 |]
let leap_year_table     = [| 0; 31; 60; 91; 121; 152; 182; 213; 244; 274; 305; 335 |]
let ordinal_date t =
  let table = if is_leap_year ~year:(year t) then leap_year_table else non_leap_year_table in
  let offset = table.(Month.to_int (month t) - 1) in
  day t + offset
;;

let last_week_of_year y =
  let first_of_year = create_exn ~y ~m:Jan ~d:1 in
  let is t day = Day_of_week.equal (day_of_week t) day in
  if is first_of_year Thu || (is_leap_year ~year:y && is first_of_year Wed)
  then 53
  else 52
;;

(* See http://en.wikipedia.org/wiki/ISO_week_date or ISO 8601 for the details of this
   algorithm. *)
let week_number t =
  let ordinal = ordinal_date t in
  let weekday = Day_of_week.iso_8601_weekday_number (day_of_week t) in
  (* [ordinal - weekday + 4] is the ordinal of this week's Thursday, then (n + 6) / 7 is
     division by 7 rounding up *)
  let week = (ordinal - weekday + 10) / 7 in
  let year = year t in
  if Int.(<) week 1
  then last_week_of_year (year - 1)
  else begin
    if Int.(>) week (last_week_of_year year)
    then 1
    else week
  end
;;

let%test_module "week_number" =
  (module struct
    let%test_unit _ = [%test_result: int] (ordinal_date (create_exn ~y:2014 ~m:Jan ~d:1)) ~expect:1
    let%test_unit _ = [%test_result: int] (ordinal_date (create_exn ~y:2014 ~m:Dec ~d:31)) ~expect:365
    let%test_unit _ = [%test_result: int] (ordinal_date (create_exn ~y:2014 ~m:Feb ~d:28)) ~expect:59

    let test_week_number y m d ~expect =
      [%test_result: int] (week_number (create_exn ~y ~m ~d)) ~expect

    let%test_unit _ = test_week_number 2014 Jan  1 ~expect:1
    let%test_unit _ = test_week_number 2014 Dec 31 ~expect:1
    let%test_unit _ = test_week_number 2010 Jan  1 ~expect:53
    let%test_unit _ = test_week_number 2017 Jan  1 ~expect:52
    let%test_unit _ = test_week_number 2014 Jan 10 ~expect:2
    let%test_unit _ = test_week_number 2012 Jan  1 ~expect:52
    let%test_unit _ = test_week_number 2012 Dec 31 ~expect:1
  end)

let is_weekend t =
  Day_of_week.is_sun_or_sat (day_of_week t)
;;

let is_weekday t = not (is_weekend t)

let is_business_day t ~is_holiday =
  is_weekday t
  && not (is_holiday t)
;;

let rec diff_weekend_days t1 t2 =
  if t1 < t2
  then - diff_weekend_days t2 t1
  else
    (* Basic date diff *)
    let diff = diff t1 t2 in
    (* Compute the number of Saturday -> Sunday crossings *)
    let d1 = day_of_week t1 in
    let d2 = day_of_week t2 in
    let num_satsun_crossings =
      if Int.(<) (Day_of_week.to_int d1) (Day_of_week.to_int d2)
      then 1 + diff / 7
      else diff / 7
    in
    num_satsun_crossings * 2
    + (if Day_of_week.(=) d2 Day_of_week.Sun then 1 else 0)
    + (if Day_of_week.(=) d1 Day_of_week.Sun then -1 else 0)

let diff_weekdays t1 t2 =
  diff t1 t2 - diff_weekend_days t1 t2

let%test_module "diff_weekdays" =
  (module struct
    let c y m d = create_exn ~y ~m ~d

    let%test "2014 Jan 1 is a Wednesday" = Day_of_week.(=) (day_of_week (c 2014 Jan 1)) Day_of_week.Wed

    let (=) = Int.(=)
    (* future minus Wednesday *)
    let%test _ = diff_weekdays (c 2014 Jan  1) (c 2014 Jan  1) = 0
    let%test _ = diff_weekdays (c 2014 Jan  2) (c 2014 Jan  1) = 1
    let%test _ = diff_weekdays (c 2014 Jan  3) (c 2014 Jan  1) = 2
    let%test _ = diff_weekdays (c 2014 Jan  4) (c 2014 Jan  1) = 3
    let%test _ = diff_weekdays (c 2014 Jan  5) (c 2014 Jan  1) = 3
    let%test _ = diff_weekdays (c 2014 Jan  6) (c 2014 Jan  1) = 3
    let%test _ = diff_weekdays (c 2014 Jan  7) (c 2014 Jan  1) = 4
    let%test _ = diff_weekdays (c 2014 Jan  8) (c 2014 Jan  1) = 5
    let%test _ = diff_weekdays (c 2014 Jan  9) (c 2014 Jan  1) = 6
    let%test _ = diff_weekdays (c 2014 Jan 10) (c 2014 Jan  1) = 7
    let%test _ = diff_weekdays (c 2014 Jan 11) (c 2014 Jan  1) = 8
    let%test _ = diff_weekdays (c 2014 Jan 12) (c 2014 Jan  1) = 8
    let%test _ = diff_weekdays (c 2014 Jan 13) (c 2014 Jan  1) = 8
    let%test _ = diff_weekdays (c 2014 Jan 14) (c 2014 Jan  1) = 9

    (* Wednesday minus future *)
    let%test _ = diff_weekdays (c 2014 Jan  1) (c 2014 Jan  2) = (-1)
    let%test _ = diff_weekdays (c 2014 Jan  1) (c 2014 Jan  3) = (-2)
    let%test _ = diff_weekdays (c 2014 Jan  1) (c 2014 Jan  4) = (-3)
    let%test _ = diff_weekdays (c 2014 Jan  1) (c 2014 Jan  5) = (-3)
    let%test _ = diff_weekdays (c 2014 Jan  1) (c 2014 Jan  6) = (-3)
    let%test _ = diff_weekdays (c 2014 Jan  1) (c 2014 Jan  7) = (-4)
    let%test _ = diff_weekdays (c 2014 Jan  1) (c 2014 Jan  8) = (-5)
    let%test _ = diff_weekdays (c 2014 Jan  1) (c 2014 Jan  9) = (-6)

    (* diff_weekend_days *)
    let%test _ = diff_weekend_days (c 2014 Jan  1) (c 2014 Jan  1) = 0
    let%test _ = diff_weekend_days (c 2014 Jan  2) (c 2014 Jan  1) = 0
    let%test _ = diff_weekend_days (c 2014 Jan  3) (c 2014 Jan  1) = 0
    let%test _ = diff_weekend_days (c 2014 Jan  4) (c 2014 Jan  1) = 0
    let%test _ = diff_weekend_days (c 2014 Jan  5) (c 2014 Jan  1) = 1
    let%test _ = diff_weekend_days (c 2014 Jan  6) (c 2014 Jan  1) = 2
    let%test _ = diff_weekend_days (c 2014 Jan  7) (c 2014 Jan  1) = 2
    let%test _ = diff_weekend_days (c 2014 Jan  8) (c 2014 Jan  1) = 2
    let%test _ = diff_weekend_days (c 2014 Jan  9) (c 2014 Jan  1) = 2
    let%test _ = diff_weekend_days (c 2014 Jan 10) (c 2014 Jan  1) = 2
    let%test _ = diff_weekend_days (c 2014 Jan 11) (c 2014 Jan  1) = 2
    let%test _ = diff_weekend_days (c 2014 Jan 12) (c 2014 Jan  1) = 3
    let%test _ = diff_weekend_days (c 2014 Jan 13) (c 2014 Jan  1) = 4
    let%test _ = diff_weekend_days (c 2014 Jan 14) (c 2014 Jan  1) = 4
  end)


let add_days_skipping t ~skip n =
  let step = if Int.(>=) n 0 then 1 else -1 in
  let rec loop t k =
    let t_next = add_days t step in
    if skip t then loop t_next k
    else if Int.(=) k 0 then t
    else loop t_next (k - 1)
  in
  loop t (abs n)

let add_weekdays t n = add_days_skipping t ~skip:is_weekend n

let add_business_days t ~is_holiday n =
  add_days_skipping t n ~skip:(fun d -> is_weekend d || is_holiday d)
;;

let dates_between ~min:t1 ~max:t2 =
  let rec loop t l =
    if t < t1 then l
    else loop (add_days t (-1)) (t::l)
  in
  loop t2 []
;;

let%test_module "ordinal_date" =
  (module struct
    (* check the ordinal date tables we found on wikipedia... *)
    let check_table year ordinal_date_table =
      let days_of_year =
        dates_between
          ~min:(create_exn ~y:year ~m:Month.Jan ~d:01)
          ~max:(create_exn ~y:year ~m:Month.Dec ~d:31)
      in
      [%test_result: int] (List.length days_of_year) ~expect:(if is_leap_year ~year then 366 else 365);
      let months = List.group days_of_year ~break:(fun d d' -> Month.(<>) (month d) (month d')) in
      let sum =
        List.foldi months ~init:0 ~f:(fun index sum month ->
          [%test_result: int] sum ~expect:ordinal_date_table.(index);
          sum + List.length month)
      in
      [%test_result: int] sum ~expect:(List.length days_of_year)
    ;;

    let%test_unit _ = check_table 2015 non_leap_year_table
    let%test_unit _ = check_table 2000 leap_year_table
  end)

let weekdays_between ~min ~max =
  let all_dates = dates_between ~min ~max in
  Option.value_map
    (List.hd all_dates)
    ~default:[]
    ~f:(fun first_date ->
      (* to avoid a system call on every date, we just get the weekday for the first
         date and use it to get all the other weekdays *)
      let first_weekday = day_of_week first_date in
      let date_and_weekdays =
        List.mapi all_dates
          ~f:(fun i date -> date,Day_of_week.shift first_weekday i) in
      List.filter_map date_and_weekdays
        ~f:(fun (date,weekday) ->
          if Day_of_week.is_sun_or_sat weekday
          then None
          else Some date)
    )
;;


let%test_module "weekdays_between" =
  (module struct
    let c y m d = create_exn ~y ~m ~d
    (* systematic test of consistency between [weekdays_between] and [diff_weekdays] *)
    let dates = [
      c 2014 Jan  1;
      c 2014 Jan  2;
      c 2014 Jan  3;
      c 2014 Jan  4;
      c 2014 Jan  5;
      c 2014 Jan  6;
      c 2014 Jan  7;
      c 2014 Feb  15;
      c 2014 Feb  16;
      c 2014 Feb  17;
      c 2014 Feb  18;
      c 2014 Feb  19;
      c 2014 Feb  20;
      c 2014 Feb  21;
    ]
    let (=) = Int.(=)
    let%test_unit _ =
      List.iter dates ~f:(fun date1 ->
        List.iter dates ~f:(fun date2 ->
          if date1 <= date2
          then assert (List.length (weekdays_between ~min:date1 ~max:(add_days date2 (-1)))
                       = diff_weekdays date2 date1);
        ))
  end)


let business_dates_between ~min ~max ~is_holiday =
  weekdays_between ~min ~max
  |> List.filter ~f:(fun d -> not (is_holiday d))
;;

let rec previous_weekday t =
  let previous_day = add_days t (-1) in
  if is_weekday previous_day then
    previous_day
  else
    previous_weekday previous_day
;;

let rec following_weekday t =
  let following_day = add_days t 1 in
  if is_weekday following_day then
    following_day
  else
    following_weekday following_day
;;

let first_strictly_after t ~on:dow =
  let dow     = Day_of_week.to_int dow in
  let tplus1  = add_days t 1 in
  let cur     = Day_of_week.to_int (day_of_week tplus1) in
  let diff    = (dow + 7 - cur) mod 7 in
  add_days tplus1 diff
;;

let%test_module "first_strictly_after" =
  (module struct
    let mon1 = create_exn ~y:2013 ~m:Month.Apr ~d:1
    let tue1 = create_exn ~y:2013 ~m:Month.Apr ~d:2
    let wed1 = create_exn ~y:2013 ~m:Month.Apr ~d:3
    let thu1 = create_exn ~y:2013 ~m:Month.Apr ~d:4
    let fri1 = create_exn ~y:2013 ~m:Month.Apr ~d:5
    let sat1 = create_exn ~y:2013 ~m:Month.Apr ~d:6
    let sun1 = create_exn ~y:2013 ~m:Month.Apr ~d:7
    let mon2 = create_exn ~y:2013 ~m:Month.Apr ~d:8
    let tue2 = create_exn ~y:2013 ~m:Month.Apr ~d:9

    let%test _ = equal (first_strictly_after tue1 ~on:Day_of_week.Mon) mon2
    let%test _ = equal (first_strictly_after tue1 ~on:Day_of_week.Tue) tue2
    let%test _ = equal (first_strictly_after tue1 ~on:Day_of_week.Wed) wed1
    let%test _ = equal (first_strictly_after tue1 ~on:Day_of_week.Thu) thu1
    let%test _ = equal (first_strictly_after tue1 ~on:Day_of_week.Fri) fri1
    let%test _ = equal (first_strictly_after tue1 ~on:Day_of_week.Sat) sat1
    let%test _ = equal (first_strictly_after tue1 ~on:Day_of_week.Sun) sun1
    let%test _ = equal (first_strictly_after mon1 ~on:Day_of_week.Mon) mon2
    let%test _ = equal (first_strictly_after mon1 ~on:Day_of_week.Tue) tue1
    let%test _ = equal (first_strictly_after mon1 ~on:Day_of_week.Wed) wed1
    let%test _ = equal (first_strictly_after mon1 ~on:Day_of_week.Thu) thu1
    let%test _ = equal (first_strictly_after mon1 ~on:Day_of_week.Fri) fri1
    let%test _ = equal (first_strictly_after mon1 ~on:Day_of_week.Sat) sat1
    let%test _ = equal (first_strictly_after mon1 ~on:Day_of_week.Sun) sun1
  end)

module For_quickcheck = struct
  open Quickcheck

  let gen_uniform_incl d1 d2 =
    if d1 > d2 then begin
      raise_s [%message
        "Date.gen_uniform_incl: bounds are crossed"
          ~lower_bound:(d1 : t)
          ~upper_bound:(d2 : t)]
    end;
    Generator.map (Int.gen_uniform_incl 0 (diff d2 d1)) ~f:(fun days ->
      add_days d1 days)

  let gen_incl d1 d2 =
    Generator.weighted_union
      [  1., Generator.return d1
      ;  1., Generator.return d2
      ; 18., gen_uniform_incl d1 d2
      ]

  let gen = gen_incl (of_string "1900-01-01") (of_string "2100-01-01")

  let obs = Observer.create (fun t ~size:_ hash -> hash_fold_t hash t)

  let shrinker = Shrinker.empty ()

  let%test_unit _ =
    test_can_generate gen ~sexp_of:sexp_of_t ~f:(fun t ->
      t = of_string "1900-01-01")

  let%test_unit _ =
    test_can_generate gen ~sexp_of:sexp_of_t ~f:(fun t ->
      t = of_string "2100-01-01")

  let%test_unit _ =
    test_can_generate gen ~sexp_of:sexp_of_t ~f:(fun t ->
      of_string "1900-01-01" < t && t < of_string "2100-01-01")

  let%test_unit _ =
    test_distinct_values gen
      ~sexp_of:sexp_of_t
      ~compare
      ~trials:1_000
      ~distinct_values:500
end

let gen              = For_quickcheck.gen
let gen_incl         = For_quickcheck.gen_incl
let gen_uniform_incl = For_quickcheck.gen_uniform_incl
let obs              = For_quickcheck.obs
let shrinker         = For_quickcheck.shrinker
