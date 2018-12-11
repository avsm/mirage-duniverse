
module Test_result : sig
  type t = Success | Failure | Error

  val combine : t -> t -> t
  val combine_all : t list -> t

  val to_string : t -> string
end

type config = (module Inline_test_config.S)
type 'a test_function_args
   = config:config
  -> descr:string
  -> tags:string list
  -> filename:string
  -> line_number:int
  -> start_pos:int
  -> end_pos:int
  -> 'a
val set_lib_and_partition : string -> string -> unit
val unset_lib : string -> unit
val test : ((unit -> bool) -> unit) test_function_args
val test_unit : ((unit -> unit) -> unit) test_function_args
val test_module : ((unit -> unit) -> unit) test_function_args
val summarize : unit -> Test_result.t
  [@@deprecated "[since 2016-04] use add_evaluator instead"]

(** These values are meant to be used inside a user's tests. *)
val collect : (unit -> unit) -> (unit -> unit) list
val testing : bool
val use_color : bool
val in_place : bool
val diff_command : string option
val source_tree_root : string option

(** Allow patterns in tests expectation *)
val allow_output_patterns : bool

(** [am_running_inline_test] is [true] if the code is running inline tests
    (e.g. [let%expect_test], [let%test], [let%test_unit]) or is in an executable
    invoked from inline tests.  The latter is arranged by setting an environment
    variable, see [Core.Am_running_inline_test]. *)
val am_running_inline_test : bool
val am_running_inline_test_env_var : string

(** Record an evaluator for an external set of tests *)
val add_evaluator : f:(unit -> Test_result.t) -> unit

(** Exit with a status based on the combined result of all recorded evaluators *)
val exit : unit -> _
