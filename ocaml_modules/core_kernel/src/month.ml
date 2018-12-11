open! Import

module Stable = struct
  module V1 = struct
    type t =
      | Jan
      | Feb
      | Mar
      | Apr
      | May
      | Jun
      | Jul
      | Aug
      | Sep
      | Oct
      | Nov
      | Dec
    [@@deriving sexp, compare, hash, variants]

    let failwithf = Printf.failwithf

    let of_int_exn i : t =
      match i with
      | 1  -> Jan
      | 2  -> Feb
      | 3  -> Mar
      | 4  -> Apr
      | 5  -> May
      | 6  -> Jun
      | 7  -> Jul
      | 8  -> Aug
      | 9  -> Sep
      | 10 -> Oct
      | 11 -> Nov
      | 12 -> Dec
      | _  -> failwithf "Month.of_int_exn %d" i ()

    let of_int i =
      try
        Some (of_int_exn i)
      with
      | _ -> None

    let to_int (t:t) =
      match t with
      | Jan -> 1
      | Feb -> 2
      | Mar -> 3
      | Apr -> 4
      | May -> 5
      | Jun -> 6
      | Jul -> 7
      | Aug -> 8
      | Sep -> 9
      | Oct -> 10
      | Nov -> 11
      | Dec -> 12

    include Binable.Stable.Of_binable.V1 (Int) (struct
        type nonrec t = t
        let to_binable t = to_int t - 1
        let of_binable i = of_int_exn (i + 1)
      end)
  end

  let%test_module "Month.V1" = (module Stable_unit_test.Make(struct
      include V1
      let equal t1 t2 = Int.(=) 0 (compare t1 t2)
      let tests =
        let module V = Variant in
        let c rank sexp bin_io tests variant =
          assert (variant.V.rank = rank);
          (variant.V.constructor, sexp, bin_io) :: tests
        in
        Variants.fold ~init:[]
          ~jan:(c 0 "Jan" "\000")
          ~feb:(c 1 "Feb" "\001")
          ~mar:(c 2 "Mar" "\002")
          ~apr:(c 3 "Apr" "\003")
          ~may:(c 4 "May" "\004")
          ~jun:(c 5 "Jun" "\005")
          ~jul:(c 6 "Jul" "\006")
          ~aug:(c 7 "Aug" "\007")
          ~sep:(c 8 "Sep" "\008")
          ~oct:(c 9 "Oct" "\009")
          ~nov:(c 10 "Nov" "\010")
          ~dec:(c 11 "Dec" "\011")
    end))
end

let num_months = 12

module T = struct
  include Stable.V1

  let all = [
    Jan
  ; Feb
  ; Mar
  ; Apr
  ; May
  ; Jun
  ; Jul
  ; Aug
  ; Sep
  ; Oct
  ; Nov
  ; Dec ]

  let%test _ = List.length all = num_months

  let%test_unit _ =
    [%test_result: t]
      (List.fold (List.tl_exn all) ~init:Jan ~f:(fun last cur ->
         assert (compare last cur = (-1));
         cur))
      ~expect:Dec

  let hash = to_int
end
include T

include (Hashable.Make_binable (struct
           include T
         end) : Hashable.S_binable with type t := t)

include Comparable.Make_binable (struct
    include T

    (* In 108.06a and earlier, months in sexps of Maps and Sets were raw ints.  From 108.07
       through 109.13, the output format remained raw as before, but both the raw and
       pretty format were accepted as input.  From 109.14 on, the output format was
       changed from raw to pretty, while continuing to accept both formats.  Once we believe
       most programs are beyond 109.14, we will switch the input format to no longer accept
       raw. *)
    let t_of_sexp sexp =
      match Option.try_with (fun () -> Int.t_of_sexp sexp) with
      | Some i -> of_int_exn (i + 1)
      | None -> T.t_of_sexp sexp
    ;;
  end)

(* Replace the overriden sexp converters from [Comparable.Make_binable] with the ordinary
   symbolic converters. *)
let sexp_of_t = T.sexp_of_t
let t_of_sexp = T.t_of_sexp

let%test _ = Set.equal (Set.of_list [Jan]) (Set.t_of_sexp Sexp.(List [Atom "0"]))
let%test _ = Pervasives.(=) (sexp_of_t Jan) (Sexp.Atom "Jan")
let%test _ = Jan = t_of_sexp (Sexp.Atom "Jan")
let%test _ = Option.is_none (Option.try_with (fun () -> t_of_sexp (Sexp.Atom "0")))

let shift t i = of_int_exn (1 + (Int.( % ) (to_int t - 1 + i) num_months))
let%test _ = shift Jan 12 = Jan
let%test _ = shift Jan (-12) = Jan
let%test _ = shift Jan 16 = May
let%test _ = shift Jan (-16) = Sep
let%test _ = shift Sep 1 = Oct
let%test _ = shift Sep (-1) = Aug

let all_strings = lazy
  (Array.of_list
     (List.map all ~f:(fun variant ->
        Sexp.to_string (sexp_of_t variant))))
;;

let to_string (t:t) =
  let all_strings = Lazy.force all_strings in
  all_strings.(to_int t - 1)
;;

let of_string =
  let table = lazy (
    let module T = String.Table in
    let table = T.create ~size:num_months () in
    Array.iteri (Lazy.force all_strings) ~f:(fun i s ->
      let t = of_int_exn (i + 1) in
      Hashtbl.set table ~key:s ~data:t;
      Hashtbl.set table ~key:(String.lowercase s) ~data:t;
      Hashtbl.set table ~key:(String.uppercase s) ~data:t);
    table)
  in
  fun str ->
    match Hashtbl.find (Lazy.force table) str with
    | Some x -> x
    | None   -> failwithf "Invalid month: %s" str ()
;;

module Export = struct
  type month = t = Jan | Feb | Mar | Apr | May | Jun | Jul | Aug | Sep | Oct | Nov | Dec
end
