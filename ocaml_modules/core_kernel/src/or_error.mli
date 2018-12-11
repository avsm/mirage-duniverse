(** This module extends {{!Base.Or_error}[Base.Or_error]} with bin_io. *)

open! Import

type 'a t = ('a, Error.t) Result.t [@@deriving bin_io]

include module type of struct include Base.Or_error end
  with type 'a t := 'a t (** @open *)

module Stable : sig
  (** [Or_error.t] is wire compatible with [V2.t], but not [V1.t], like [Info.Stable]
      and [Error.Stable]. *)
  module V1 : Stable_module_types.S1 with type 'a t = 'a t
  module V2 : Stable_module_types.S1 with type 'a t = 'a t
end
