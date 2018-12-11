(** [Core_kernel] greatly expands the functionality available in Base while still
    remaining platform-agnostic.  Core_kernel changes more frequently (i.e., is less
    stable) than Base.

    Some modules are mere extensions of their counterparts in Base, usually adding generic
    functionality by including functors that make them binable, comparable, sexpable,
    blitable, etc.  The bulk of Core_kernel, though, is modules providing entirely new
    functionality.

    It is broken in two pieces, [Std_kernel] and [Std], where the first includes modules
    that aren't overridden by [Core], and the second defines modules that are. *)

open! Import

(** {1 Std_kernel}

    [Std_kernel] defines modules exposed by [Core_kernel] that are not overridden by
    [Core]. It is used in [core.ml] to re-export these modules. *)

(** {2 Modules imported from Base without modification} *)

module Applicative               = Applicative
module Avltree                   = Avltree
module Backtrace                 = Backtrace
module Bin_prot                  = Core_bin_prot
module Binary_search             = Binary_search
module Commutative_group         = Commutative_group
module Comparisons               = Comparisons
module Equal                     = Equal
module Exn                       = Base.Exn
module Expect_test_config        = Expect_test_config
module Field                     = Field
module Floatable                 = Floatable
module Hash                      = Hash
module Heap_block                = Heap_block
module In_channel                = In_channel
module Int_conversions           = Base.Not_exposed_properly.Int_conversions
module Invariant                 = Invariant
module Monad                     = Monad
module Obj_array                 = Base.Not_exposed_properly.Obj_array
module Ordered_collection_common = Ordered_collection_common
module Out_channel               = Out_channel
module Poly                      = Poly
module Polymorphic_compare       = Polymorphic_compare
module Pretty_printer            = Pretty_printer
module Random                    = Base.Random
module Sexp_maybe                = Sexp.Sexp_maybe
module Staged                    = Base.Staged
module Stringable                = Stringable
module Validate                  = Validate
module With_return               = With_return
module Word_size                 = Word_size

(** {2 Modules that extend Base} *)

module Array                = Array
module Binary_searchable    = Binary_searchable
module Blit                 = Blit
module Bool                 = Bool
module Bytes                = Bytes
module Char                 = Char
module Comparable           = Comparable
module Comparator           = Comparator
module Container            = Container
module Either               = Either
module Error                = Error
module Float                = Float
module Fn                   = Fn
module Hash_set             = Hash_set
module Hashtbl              = Hashtbl
module Hashtbl_intf         = Hashtbl_intf
module Info                 = Info
module Int                  = Int
module Int_intf             = Int_intf
module Int32                = Int32
module Int63                = Int63
module Int64                = Int64
module Lazy                 = Lazy
module Linked_queue         = Linked_queue
module List                 = List
module Maybe_bound          = Maybe_bound
module Nativeint            = Nativeint
module Option               = Option
module Ordering             = Ordering
module Or_error             = Or_error
module Printf               = Printf
module Ref                  = Ref
module Result               = Result
module Sequence             = Sequence
module Set                  = Set
module Sexp                 = Sexp
module Sexpable             = Sexpable
module Sign                 = Sign
module Source_code_position = Source_code_position
module String               = String
module Type_equal           = Type_equal
module Unit                 = Unit

(** {2 Modules added by Core_kernel} *)

module Arg                                  = Arg
module Bag                                  = Bag
module Bigsubstring                         = Bigsubstring
module Binable                              = Binable
module Binary_packing                       = Binary_packing
module Blang                                = Blang
module Bounded_index                        = Bounded_index
module Bounded_int_table                    = Bounded_int_table
module Bucket                               = Bucket
module Bus                                  = Bus
module Byte_units                           = Byte_units
module Day_of_week                          = Day_of_week
module Debug                                = Debug
module Deque                                = Deque
module Deriving_hash                        = Deriving_hash
module Doubly_linked                        = Doubly_linked
module Ephemeron                            = Ephemeron
module Fdeque                               = Fdeque
module Fheap                                = Fheap
module Flags                                = Flags
module Float_with_finite_only_serialization = Float_with_finite_only_serialization
module Force_once                           = Force_once
module Fqueue                               = Fqueue
module Gc                                   = Gc
module Hash_heap                            = Hash_heap
module Hash_queue                           = Hash_queue
module Hashable                             = Hashable
module Heap                                 = Heap
module Hexdump                              = Hexdump
module Hexdump_intf                         = Hexdump_intf
module Host_and_port                        = Host_and_port
module Identifiable                         = Identifiable
module Immediate_option                     = Immediate_option
module Immediate_option_intf                = Immediate_option_intf
module Int_set                              = Int_set
module Interfaces                           = Interfaces
module Limiter                              = Limiter
module Linked_stack                         = Linked_stack
module Map                                  = Map
module Memo                                 = Memo
module Month                                = Month
module Moption                              = Moption
module No_polymorphic_compare               = No_polymorphic_compare
module Nothing                              = Nothing
module Only_in_test                         = Only_in_test
module Option_array                         = Option_array
module Optional_syntax                      = Optional_syntax
module Percent                              = Percent
module Pid                                  = Pid
module Pool                                 = Pool
module Pool_intf                            = Pool_intf
module Pooled_hashtbl                       = Pooled_hashtbl
module Printexc                             = Printexc
module Queue                                = Queue
module Quickcheck                           = Quickcheck
module Quickcheck_intf                      = Quickcheck_intf
module Quickcheckable                       = Quickcheckable
module Robustly_comparable                  = Robustly_comparable
module Rope                                 = Rope
module Set_once                             = Set_once
module Splittable_random                    = Splittable_random
module Stable_comparable                    = Stable_comparable
module Stable_unit_test                     = Stable_unit_test
module Stack                                = Stack
module String_id                            = String_id
module Substring                            = Substring
module Substring_intf                       = Substring_intf
module Thread_safe_queue                    = Thread_safe_queue
module Timing_wheel_ns                      = Timing_wheel_ns
module Total_map                            = Total_map
module Tuple                                = Tuple
module Tuple_type                           = Tuple_type
module Tuple2                               = Tuple.T2
module Tuple3                               = Tuple.T3
module Type_immediacy                       = Type_immediacy
module Uniform_array                        = Uniform_array
module Union_find                           = Union_find
module Unique_id                            = Unique_id
module Unit_of_time                         = Unit_of_time
module Univ                                 = Univ
module Univ_map                             = Univ_map
module Unpack_buffer                        = Unpack_buffer
module Validated                            = Validated
module Weak                                 = Weak
module Weak_pointer                         = Weak_pointer

module type Unique_id = Unique_id.Id

include T (** @open *)

(** {2 Top-level values} *)

type 'a _maybe_bound = 'a Maybe_bound.t =
    Incl of 'a | Excl of 'a | Unbounded

let does_raise = Exn.does_raise

type bytes =
  [ `This_type_does_not_equal_string_because_we_want_type_errors_to_say_string ]
;;

(** We perform these side effects here because we want them to run for any code that uses
    [Core_kernel].  If this were in another module in [Core_kernel] that was not used in
    some program, then the side effects might not be run in that program.  This will run
    as long as the program refers to at least one value directly in [Std_kernel];
    referring to values in [Std_kernel.Bool], for example, is not sufficient. *)
let () =
  Exn.initialize_module ();
;;

let am_running_inline_test = Ppx_inline_test_lib.Runtime.am_running_inline_test

let sec = Time_float.Span.of_sec

include Std_internal

include Not_found
