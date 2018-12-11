open! Core_kernel
open Or_error

let%test_unit "[error_s] produces a value with the expected [sexp_of_t]" =
  let sexp = [%sexp "foo"] in
  match [%sexp (error_s sexp : _ t)] with
  | List [ Atom "Error"; sexp2 ] -> assert (phys_equal sexp sexp2);
  | _ -> assert false;
;;

let%test _ = Result.is_error (filter_ok_at_least_one [])
let%test_unit _ =
  for i = 1 to 10; do
    assert (filter_ok_at_least_one (List.init i ~f:(fun _ -> Ok ()))
            = Ok (List.init i ~f:(fun _ -> ())));
  done
let%test _ =
  let a = Error.of_string "a" and b = Error.of_string "b" in
  match filter_ok_at_least_one [Ok 1; Error a; Ok 2; Error b] with
  | Ok x -> x = [1;2]
  | Error _ -> false
let%test _ =
  let a = Error.of_string "a" and b = Error.of_string "b" in
  match filter_ok_at_least_one [Error a; Error b] with
  | Ok _ -> false
  | Error e -> Error.to_string_hum e = Error.to_string_hum (Error.of_list [a;b])


let%test _ = Result.is_error (find_ok [])
let%test _ =
  let a = Error.of_string "a" and b = Error.of_string "b" in
  match find_ok [Error a; Ok 1; Error b] with
  | Ok x -> x = 1
  | Error _ -> false
let%test _ =
  let a = Error.of_string "a" and b = Error.of_string "b" in
  match find_ok [Error a; Error b; Ok 2; Ok 3] with
  | Ok x -> x = 2
  | Error _ -> false
let%test _ =
  let a = Error.of_string "a" and b = Error.of_string "b" in
  match find_ok [Error a; Error b] with
  | Ok _ -> false
  | Error e -> Error.to_string_hum e = Error.to_string_hum (Error.of_list [a;b])

let%test _ =
  Result.is_error (find_map_ok ~f:(fun _ -> assert false) [])
let%test _ =
  try (let _ = find_map_ok ~f:(fun _ -> raise (Failure "abc")) [1] in false) with
  | Failure "abc" -> true
  | _ -> false
let%test _ =
  let a = Error.of_string "a" and b = Error.of_string "b" in
  match find_map_ok ~f:Fn.id [Error a; Ok 1; Error b] with
  | Ok x -> x = 1
  | Error _ -> false
let%test _ =
  let a = Error.of_string "a" and b = Error.of_string "b" in
  match find_map_ok ~f:Fn.id [Error a; Error b; Ok 2; Ok 3;] with
  | Ok x -> x = 2
  | Error _ -> false
let%test _ =
  let a = Error.of_string "a" and b = Error.of_string "b" in
  match find_map_ok ~f:Fn.id [Error a; Error b] with
  | Ok _ -> false
  | Error e -> Error.to_string_hum e = Error.to_string_hum (Error.of_list [a;b])
