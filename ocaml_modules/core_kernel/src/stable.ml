module Unit_test = Stable_unit_test.Make

(* miscellaneous unit tests that can't be put in their respective .mls due to circular
   dependencies *)
module Unit_tests = struct
  let%test_module "Result.V1" = (module Unit_test(Result.Stable.V1_stable_unit_test))
end


module type Stable                    = Stable_module_types.S0
module type Stable_without_comparator = Stable_module_types.S0_without_comparator
module type Stable1                   = Stable_module_types.S1
module type Stable2                   = Stable_module_types.S2
module type Stable3                   = Stable_module_types.S3
module type Stable4                   = Stable_module_types.S4

module Make_stable = Make_stable

include Stable_internal
include Stable_containers

module Binable                              = Binable                              .Stable
module Blang                                = Blang                                .Stable
module Byte_units                           = Byte_units                           .Stable
module Comparable                           = Comparable                           .Stable
module Comparator                           = Comparator                           .Stable
module Date                                 = Date                                 .Stable
module Day_of_week                          = Day_of_week                          .Stable
module Md5                                  = Md5                                  .Stable
module Either                               = Either                               .Stable
module Error                                = Error                                .Stable
module Fdeque                               = Fdeque                               .Stable
module Float_with_finite_only_serialization = Float_with_finite_only_serialization .Stable
module Fqueue                               = Fqueue                               .Stable
module Host_and_port                        = Host_and_port                        .Stable
module Info                                 = Info                                 .Stable
module Int                                  = Int                                  .Stable
module Int63                                = Int63                                .Stable
module Lazy                                 = Lazy                                 .Stable
module Map                                  = Map                                  .Stable
module Month                                = Month                                .Stable
module Nothing                              = Nothing                              .Stable
module Or_error                             = Or_error                             .Stable
module Percent                              = Percent                              .Stable
module Perms                                = Perms                                .Stable
module Pid                                  = Pid                                  .Stable
module Queue                                = Queue                                .Stable
module Result                               = Result                               .Stable
module Set                                  = Set                                  .Stable
module Sexpable                             = Sexpable                             .Stable
module Source_code_position                 = Source_code_position                 .Stable
module String                               = String                               .Stable
module String_id                            = String_id                            .Stable
module Time_ns                              = Time_ns                              .Stable
module Time                                 = Time_float                           .Stable

include Perms.Export

include Ppx_compare_lib.Builtin

include Import.Not_found
