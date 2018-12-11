open! Import

include Doubly_linked

let add = insert_first

let elts t = fold_elt t ~init:[] ~f:(fun acc elt -> elt :: acc)

let remove_one = remove_first

let choose = first_elt

let until_empty t f =
  let rec loop () =
    Option.iter (remove_one t) ~f:(fun v -> f v; loop ())
  in
  loop ()
;;
