open! Import

module Binable = Binable0

(* All the types as exposed in the mli are defined in this [Types] module.  The rest of
   this file is simply overriding all the bin_io, compare, and sexp functions to raise
   exceptions. *)
module Types = struct
  module Nobody = struct
    type t [@@deriving bin_io, compare, hash, sexp]
    let name = "Nobody"
  end

  module Me = struct
    type t [@@deriving bin_io, compare, hash, sexp]
    let name = "Me"
  end

  module Read = struct
    type t = [ `Read ]
    [@@deriving bin_io, compare, hash, sexp]
    let name = "Read"
  end

  module Write = struct
    type t = [ `Who_can_write of Me.t ]
    [@@deriving bin_io, compare, hash, sexp]
    let name = "Write"
  end

  module Immutable = struct
    type t = [ Read.t | `Who_can_write of Nobody.t ]
    [@@deriving bin_io, compare, hash, sexp]
    let name = "Immutable"
  end

  module Read_write = struct
    type t = [ Read.t | Write.t ]
    [@@deriving bin_io, compare, hash, sexp]
    let name = "Read_write"
  end

  module Upper_bound = struct
    type 'a t = [ Read.t | `Who_can_write of 'a ]
    [@@deriving bin_io, compare, hash, sexp]
    let name = "Upper_bound"
  end
end

let failwithf = Printf.failwithf

(* This is an explicit module type instead of just given inline as the return signature of
   [Only_used_as_phantom_type1] to avoid an unused value warning with bin_io values. *)
module type Sexpable_binable_comparable = sig
  type 'a t = 'a [@@deriving bin_io, compare, hash, sexp]
end

(* Override all bin_io, sexp, compare functions to raise exceptions *)
module Only_used_as_phantom_type1 (Name : sig val name : string end)
  : Sexpable_binable_comparable = struct
  type 'a t = 'a
  let sexp_of_t _ _ =
    failwithf "Unexpectedly called [%s.sexp_of_t]" Name.name ()
  let t_of_sexp _ _ =
    failwithf "Unexpectedly called [%s.t_of_sexp]" Name.name ()
  let compare _ _ _ =
    failwithf "Unexpectedly called [%s.compare]" Name.name ()
  let hash_fold_t _ _ _ =
    failwithf "Unexpectedly called [%s.hash_fold_t]" Name.name ()
  include Binable.Of_binable1
      (struct type 'a t = 'a [@@deriving bin_io] end)
      (struct
        type nonrec 'a t = 'a t
        let to_binable _ =
          failwithf "Unexpectedly used %s bin_io serialization" Name.name ()
        let of_binable _ =
          failwithf "Unexpectedly used %s bin_io deserialization" Name.name ()
      end)
end

module Only_used_as_phantom_type0 (T : sig
    type t [@@deriving bin_io, compare, hash, sexp]
    val name : string
  end) : sig
  type t = T.t [@@deriving bin_io, compare, hash, sexp_poly]
end = struct
  module M = Only_used_as_phantom_type1 (T)
  type t = T.t M.t [@@deriving bin_io, compare, hash, sexp]
  let __t_of_sexp__ = t_of_sexp
end

module Stable = struct
  module V1 = struct
    module Nobody     = Only_used_as_phantom_type0 (Types.Nobody)
    module Me         = Only_used_as_phantom_type0 (Types.Me)
    module Read       = Only_used_as_phantom_type0 (Types.Read)
    module Write      = Only_used_as_phantom_type0 (Types.Write)
    module Read_write = Only_used_as_phantom_type0 (Types.Read_write)
    module Immutable  = Only_used_as_phantom_type0 (Types.Immutable)

    type nobody = Nobody.t [@@deriving bin_io, compare, hash, sexp]
    type me     = Me.t     [@@deriving bin_io, compare, hash, sexp]

    module Upper_bound = struct
      module M = Only_used_as_phantom_type1 (Types.Upper_bound)
      type 'a t = 'a Types.Upper_bound.t M.t [@@deriving bin_io, compare, hash, sexp]
      let __t_of_sexp__ = t_of_sexp
    end
  end

  module Export = struct
    type read       = V1.Read.          t [@@deriving bin_io, compare, hash, sexp]
    type write      = V1.Write.         t [@@deriving compare, hash, sexp]
    type immutable  = V1.Immutable.     t [@@deriving bin_io, compare, hash, sexp]
    type read_write = V1.Read_write.    t [@@deriving bin_io, compare, hash, sexp]
    type 'a perms   = 'a V1.Upper_bound.t [@@deriving bin_io, compare, hash, sexp]
  end
end

include Stable.V1
module Export = Stable.Export
