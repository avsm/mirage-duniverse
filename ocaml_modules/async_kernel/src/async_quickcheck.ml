open Core_kernel

open Deferred.Infix

module Generator = Quickcheck.Generator
module Observer  = Quickcheck.Observer
module Shrinker  = Quickcheck.Shrinker

module Configure (Config : Quickcheck.Quickcheck_config) = struct

  include Quickcheck.Configure (Config)

  let async_test ?seed ?(trials = default_trial_count) ?sexp_of gen ~f =
    let f_with_sexp =
      match sexp_of with
      | None -> f
      | Some sexp_of_arg ->
        (fun x ->
           Deferred.Or_error.try_with (fun () -> f x)
           >>| function
           | Ok () -> ()
           | Error e ->
             Error.raise
               (Error.tag_arg e "random input" x sexp_of_arg))
    in
    Sequence.delayed_fold
      (Sequence.take (random_sequence ?seed gen) trials)
      ~init:()
      ~f:(fun () x ~k -> f_with_sexp x >>= k)
      ~finish:Deferred.return

end

include Configure (Quickcheck)
