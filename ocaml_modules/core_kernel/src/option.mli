(** This module extends {{!Base.Option}[Base.Option]} with bin_io and quickcheck. *)

type 'a t = 'a Base.Option.t [@@deriving bin_io, typerep]

include module type of struct include Base.Option end with type 'a t := 'a t (** @open *)

include Comparator.Derived with type 'a t := 'a t
include Quickcheckable.S1 with type 'a t := 'a t

