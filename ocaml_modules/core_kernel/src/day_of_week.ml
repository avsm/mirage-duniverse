open! Import

let failwithf = Printf.failwithf

module Stable = struct
  module V1 = struct
    module T = struct
      type t =
        | Sun
        | Mon
        | Tue
        | Wed
        | Thu
        | Fri
        | Sat
      [@@deriving bin_io, compare, hash]

      let to_string t =
        match t with
        | Sun -> "SUN"
        | Mon -> "MON"
        | Tue -> "TUE"
        | Wed -> "WED"
        | Thu -> "THU"
        | Fri -> "FRI"
        | Sat -> "SAT"
      ;;

      let to_string_long t =
        match t with
        | Sun -> "Sunday"
        | Mon -> "Monday"
        | Tue -> "Tuesday"
        | Wed -> "Wednesday"
        | Thu -> "Thursday"
        | Fri -> "Friday"
        | Sat -> "Saturday"
      ;;

      let of_string_internal s =
        match String.uppercase s with
        | "SUN" | "SUNDAY"    -> Sun
        | "MON" | "MONDAY"    -> Mon
        | "TUE" | "TUESDAY"   -> Tue
        | "WED" | "WEDNESDAY" -> Wed
        | "THU" | "THURSDAY"  -> Thu
        | "FRI" | "FRIDAY"    -> Fri
        | "SAT" | "SATURDAY"  -> Sat
        | _     -> failwithf "Day_of_week.of_string: %S" s ()
      ;;

      let of_int_exn i =
        match i with
        | 0 -> Sun
        | 1 -> Mon
        | 2 -> Tue
        | 3 -> Wed
        | 4 -> Thu
        | 5 -> Fri
        | 6 -> Sat
        | _ -> failwithf "Day_of_week.of_int_exn: %d" i ()
      ;;

      (* Be very generous with of_string.  We accept all possible capitalizations and the
         integer representations as well. *)
      let of_string s =
        try
          of_string_internal s
        with
        | _ ->
          try
            of_int_exn (Int.of_string s)
          with
          | _ -> failwithf "Day_of_week.of_string: %S" s ()
      ;;

      (* this is in T rather than outside so that the later functor application to build maps
         uses this sexp representation *)
      include Sexpable.Stable.Of_stringable.V1 (struct
          type nonrec t = t
          let of_string = of_string
          let to_string = to_string
        end)
    end

    include T
    module Unstable = struct
      include T
      include (Comparable.Make_binable (T) : Comparable.S_binable with type t := t)
      include Hashable.   Make_binable (T)
    end
    include Comparable.Stable.V1.Make (Unstable)
    include Stable_containers.Hashable.V1.Make   (Unstable)
  end

  let%test_module "Day_of_week.V1" =
    (module Stable_unit_test.Make (struct
         include V1

         let equal a b = (compare a b) = 0

         let tests =
           [ Sun, "SUN", "\000"
           ; Mon, "MON", "\001"
           ; Tue, "TUE", "\002"
           ; Wed, "WED", "\003"
           ; Thu, "THU", "\004"
           ; Fri, "FRI", "\005"
           ; Sat, "SAT", "\006"
           ]
       end))
end

include Stable.V1.Unstable

let weekdays = [ Mon; Tue; Wed; Thu; Fri ]

let weekends = [ Sat; Sun ]

(* written out to save overhead when loading modules.  The members of the set and the
   ordering should never change, so speed wins over something more complex that proves
   the order = the order in t at runtime *)
let all = [ Sun; Mon; Tue; Wed; Thu; Fri; Sat ]

let%test _ = List.is_sorted all ~compare

let%test "to_string_long output parses with of_string" =
  List.for_all all ~f:(fun d -> d = (to_string_long d |> of_string))

let of_int i = try Some (of_int_exn i) with _ -> None

let to_int t =
  match t with
  | Sun -> 0
  | Mon -> 1
  | Tue -> 2
  | Wed -> 3
  | Thu -> 4
  | Fri -> 5
  | Sat -> 6
;;

let iso_8601_weekday_number t =
  match t with
  | Mon -> 1
  | Tue -> 2
  | Wed -> 3
  | Thu -> 4
  | Fri -> 5
  | Sat -> 6
  | Sun -> 7
;;

let num_days_in_week = 7

let shift t i = of_int_exn (Int.( % ) (to_int t + i) num_days_in_week)

let num_days ~from ~to_ =
  let d = to_int to_ - to_int from in
  if Int.(d < 0) then d + num_days_in_week else d
;;

let%test _ = Int.(num_days ~from:Mon ~to_:Tue = 1);;
let%test _ = Int.(num_days ~from:Tue ~to_:Mon = 6);;
let%test "num_days is inverse to shift" =
  let all_days = [Sun; Mon; Tue; Wed; Thu; Fri; Sat] in
  List.for_all (List.cartesian_product all_days all_days)
    ~f:(fun (from, to_) ->
      let i = num_days ~from ~to_ in
      Int.(0 <= i && i < num_days_in_week) && shift from i = to_)
;;

let is_sun_or_sat t = t = Sun || t = Sat
