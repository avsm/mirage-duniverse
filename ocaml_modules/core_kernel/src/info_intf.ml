open! Import

(** Extension to the base signature *)
module type Extension = sig
  type t [@@deriving bin_io]

  module Stable : sig
    (** [Info.t] is wire-compatible with [V2.t], but not [V1.t].  [V1] bin-prots a sexp of
        the underlying message, whereas [V2] bin-prots the underlying message. *)
    module V1 : Stable_module_types.S0 with type t = t
    module V2 : Stable_module_types.S0 with type t = t
  end
end

module type S = sig
  include Base.Info.S

  include Extension with type t := t
end

module type Info = sig
  include module type of struct include Base.Info end [@ocaml.remove_aliases] (** @open *)

  include Extension with type t := t

  module Extend (Info : Base.Info.S) : Extension with type t := Info.t
end
