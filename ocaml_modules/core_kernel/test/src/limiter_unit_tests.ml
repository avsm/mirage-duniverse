open! Core_kernel

module Step_test = struct
  let offset off = Time_ns.add Time_ns.epoch (Time_ns.Span.of_sec off)

  type step =
    | Take             of int * bool
    | Return_to_hopper of int
    | Return_to_bucket of int * bool
  [@@deriving sexp]

  type timed_step = (float * step) [@@deriving sexp]

  let take time amount expect : timed_step =
    (time, Take (amount,expect))
  let return_to_bucket time amount expect : timed_step =
    (time, Return_to_bucket (amount,expect))
  let return_to_hopper time amount : timed_step =
    (time, Return_to_hopper amount)

  let run t l =
    try
      List.iter l ~f:(fun (now_offset, step) ->
        Limiter.invariant t;
        let before = Limiter.sexp_of_t t in
        let now    = offset now_offset in
        begin match step with
        | Return_to_hopper amount -> Limiter.Expert.return_to_hopper t ~now (Int.abs amount)
        | Take (amount, expect) ->
          begin match Limiter.Expert.try_take t ~now amount with
          | Asked_for_more_than_bucket_limit ->
            raise_s [%message "test asked to take more than bucket size"
                                (amount : int)
                                (before : Sexp.t)
                                (t : Limiter.t)
                                (now_offset : float)]
          | Taken  ->
            if not expect
            then raise_s [%message "incorrectly able to take from the bucket"
                                     (amount : int)
                                     (before : Sexp.t)
                                     (t : Limiter.t)
                                     (now_offset : float)]
          | Unable ->
            if expect
            then raise_s [%message "unable to take from the bucket"
                                     (amount : int)
                                     (before : Sexp.t)
                                     (t : Limiter.t)
                                     (now_offset : float)]
          end
        | Return_to_bucket (amount, expect) ->
          begin match Limiter.Expert.try_return_to_bucket t ~now amount with
          | Returned_to_bucket ->
            if not expect
            then raise_s [%message "incorrectly able to return_to_bucket"
                                     (amount : int)
                                     (before : Sexp.t)
                                     (t : Limiter.t)
                                     (now_offset : float)]
          | Unable ->
            if expect
            then raise_s [%message "unable to return_to_bucket"
                                     (amount : int)
                                     (before : Sexp.t)
                                     (t : Limiter.t)
                                     (now_offset : float)]
          end
        end;
        Limiter.invariant t)
    with e ->
      Error.raise
        (Error.tag_arg (Error.of_exn e)
           "Limiter step test failed" (t,l)
           [%sexp_of: Limiter.t * timed_step list])
  ;;

  let%test_unit "return_to_hopper invariants" =
    let t =
      Limiter.Expert.create_exn
        ~now:Time_ns.epoch
        ~hopper_to_bucket_rate_per_sec:Infinite
        ~bucket_limit:10
        ~in_flight_limit:Infinite
        ~initial_bucket_level:10
        ~initial_hopper_level:(Finite 0)
    in
    [%test_result: bool]
      ~expect:true
      (Exn.does_raise (fun () -> Limiter.Expert.return_to_hopper t ~now:Time_ns.epoch 1))
  ;;

  let%test_unit "try_return_to_bucket" =
    run (Limiter.Expert.create_exn
           ~now:Time_ns.epoch
           ~hopper_to_bucket_rate_per_sec:(Finite 1.)
           ~bucket_limit:60
           ~in_flight_limit:Infinite
           ~initial_bucket_level:10
           ~initial_hopper_level:(Finite 0))
      [ return_to_bucket 0.0   1  false
      ; take             0.0   2  true
      ; return_to_bucket 1.0   1  true
      ; return_to_bucket 1.0  20  false
      ; return_to_bucket 1.0 (-2) false
      ]
  ;;

  let%test_unit "try_return_to_bucket with hopper" =
    run (Limiter.Expert.create_exn
           ~now:Time_ns.epoch
           ~hopper_to_bucket_rate_per_sec:(Finite 1.)
           ~bucket_limit:10
           ~in_flight_limit:Infinite
           ~initial_bucket_level:10
           ~initial_hopper_level:(Finite 10))
      [ take              0.0 10 true
      ; return_to_bucket  0.0 10 true
      ; take              1.0 10 true
      ; take              2.0 10 false
      ; take              2.0  1 true
      ; return_to_bucket  3.0 11 false
      ; return_to_bucket  3.0  8 true
      ; return_to_bucket 13.   2 false ]
  ;;

  let%test_unit "Generic" =
    run (Limiter.Expert.create_exn
           ~now:Time_ns.epoch
           ~hopper_to_bucket_rate_per_sec:(Finite 1.)
           ~bucket_limit:60
           ~in_flight_limit:Infinite
           ~initial_bucket_level:0
           ~initial_hopper_level:Infinite)
      [ take 0.0  1 false
      ; take 1.0  1 true
      ; take 1.0  1 false
      ; take 1.5  1 false
      ; take 60. 60 false
      ; take 60. 59 true ]

  let%test_unit "Generic" =
    run (Limiter.Expert.create_exn
           ~now:Time_ns.epoch
           ~hopper_to_bucket_rate_per_sec:(Finite 1.)
           ~bucket_limit:120
           ~in_flight_limit:Infinite
           ~initial_bucket_level:0
           ~initial_hopper_level:Infinite)
      [ take 0.0  1   false
      ; take 1.0  1   true
      ; take 1.0  1   false
      ; take 1.5  1   false
      ; take 60.  60  false
      ; take 360. 120 true
      ]

  let%test_unit "Generic" =
    run (Limiter.Expert.create_exn
           ~now:Time_ns.epoch
           ~hopper_to_bucket_rate_per_sec:(Finite 1.)
           ~bucket_limit:60
           ~in_flight_limit:Infinite
           ~initial_bucket_level:0
           ~initial_hopper_level:(Finite 10))
      [ take              1.  1 true
      ; return_to_hopper  1.  1
      ; take             10.  9 true
      ; return_to_hopper 10.  9
      ; take             11.  1 true
      ; return_to_hopper 11.  1
      ; take             15.  5 false
      ; take             15.  4 true
      ; return_to_hopper 15.  4
      ; take             30. 11 false
      ; take             30. 10 true
      ]
  ;;

  let%test_unit "Throttled_rate_limiter" =
    let limiter =
      Limiter.Throttled_rate_limiter.create_exn
        ~now:Time_ns.epoch
        ~burst_size:3
        ~sustained_rate_per_sec:(2. /. 1.)
        ~max_concurrent_jobs:5
    in
    run
      (limiter :> Limiter.t)
      [ take              0.0  1 true
      ; take              0.1  1 true
      ; take              0.2  1 true   (* we can open these jobs because of the burst size *)
      ; take              0.3  1 false  (* and now that's done *)
      ; take              0.5  1 true   (* but after 1/2 second, we have another *)
      ; take              1.0  1 true   (* and now one more.  We need to wait a bit longer than
                                           would be perfect to accomodate token drip granularity. *)
      ; take              2.0  2 false  (* but now there are too many concurrent jobs *)
      ; return_to_hopper  2.0  3        (* give some back *)
      ; take              2.0  1 false  (* and it take            s time for them to get in the bucket *)
      ; take              3.0  2 true   (* and now we can do a burst of 2 *)
      ; take             10.0  1 true   (* and one more *)
      ; take             10.0  1 false  (* but now we're out of concurrent jobs *)
      ]
  ;;

  let%test_unit "Throttle" =
    let throttle =
      Limiter.Throttle.create_exn
        ~now:Time_ns.epoch
        ~max_concurrent_jobs:3
    in
    run (throttle :> Limiter.t)
      [ take             0. 1 true
      ; take             0. 1 true
      ; take             0. 1 true
      ; take             0. 1 false
      ; return_to_hopper 1. 1
      ; take             1. 1 true ]
end
