(** Contains Async's core data structures, like {{!Async_kernel.Deferred}[Deferred]},
    {{!Async_kernel.Ivar}[Ivar]}, and {{!Async_kernel.Clock_intf.Clock}[Clock]}.

    [Async_kernel] is designed to depend only on {{!Core_kernel}[Core_kernel]} (as opposed
    to {{!Core}[Core]}), and so is more platform-independent. *)

(**/**)
module Limiter_in_this_directory = Limiter
(**/**)

open! Core_kernel
open! Import

module Async_kernel_config                       = Async_kernel_config
module Async_kernel_persistent_connection        = Persistent_connection
module Async_kernel_require_explicit_time_source = Require_explicit_time_source
module Async_kernel_scheduler                    = Scheduler
module Bvar                                      = Bvar
module Clock_ns                                  = Clock_ns
module Condition                                 = Async_condition
module Deferred                                  = Deferred
module Eager_deferred                            = Eager_deferred
module Execution_context                         = Execution_context
module Gc                                        = Async_gc
module Invariant                                 = Async_invariant
module Ivar                                      = Ivar
module Quickcheck                                = Async_quickcheck
module Lazy_deferred                             = Lazy_deferred
module Limiter                                   = Limiter_in_this_directory
module Monad_sequence                            = Monad_sequence
module Monitor                                   = Monitor
module Mvar                                      = Mvar
module Pipe                                      = Pipe
module Priority                                  = Priority
module Sequencer                                 = Throttle.Sequencer
module Stream                                    = Async_stream
module Synchronous_time_source                   = Synchronous_time_source
module Tail                                      = Tail
module Throttle                                  = Throttle
module Time_source                               = Time_source

(** Intended usage is to [open Use_eager_deferred] to shadow operations from the non-eager
    world and rebind them to their eager counterparts. *)
module Use_eager_deferred = struct
  module Deferred = struct
    type 'a t = 'a Deferred.t
    include Eager_deferred
  end
  include (Eager_deferred : Monad.Infix with type 'a t := 'a Deferred1.t)
  include Eager_deferred.Let_syntax
  let upon = Eager_deferred.upon
  let ( >>> ) = Eager_deferred.Infix.( >>> )
end


(** {2 Toplevel functions }

    The functions below are broadly useful when writing Async programs, and so are made
    available at the toplevel. *)

let after          = Clock_ns.after
let at             = Clock_ns.at
let catch          = Monitor.catch
let choice         = Deferred.choice
let choose         = Deferred.choose
let don't_wait_for = Deferred.don't_wait_for
let every          = Clock_ns.every
let never          = Deferred.never
let schedule       = Scheduler.schedule
let schedule'      = Scheduler.schedule'
let try_with       = Monitor.try_with
let upon           = Deferred.upon
let with_timeout   = Clock_ns.with_timeout
let within         = Scheduler.within
let within'        = Scheduler.within'

(** {2 Infix operators and [Let_syntax] support} *)

include (Deferred : Monad.Infix with type 'a t := 'a Deferred.t)

(** equivalent to {!Deferred.upon}. *)
let ( >>>  ) = Deferred.Infix. ( >>> )

(** equivalent to {!Deferred.Result.bind}. *)
let ( >>=? ) = Deferred.Result.( >>= )

(** equivalent to {!Deferred.Result.map}. *)
let ( >>|? ) = Deferred.Result.( >>| )

include Deferred.Let_syntax


(**/**)
(** The modules in [Async_kernel_private] are used for constructing and testing Async, and
    should not otherwise be used. *)
module Async_kernel_private = struct
  module Debug       = Debug
  module Ivar0       = Ivar0
  module Ivar_filler = Ivar_filler
  module Job         = Job
end
(**/**)

(* This test must be in this library, because it requires [return] to be inlined.  Moving
   it to another library will cause it to break with [X_LIBRARY_INLINING=false]. *)
let%test_unit "[return ()] does not allocate" =
  let w1 = Gc.minor_words () in
  ignore (return () : _ Deferred.t);
  ignore (Deferred.return () : _ Deferred.t);
  ignore (Deferred.Let_syntax.return () : _ Deferred.t);
  ignore (Deferred.Let_syntax.Let_syntax.return () : _ Deferred.t);
  let w2 = Gc.minor_words () in
  [%test_result: int] w2 ~expect:w1;
;;
