open! Import
open Std_internal

module type S = sig
  (** Time of day.

      [t] represents a clock-face time of day. Usually this is equivalent to a time-offset
      from midnight, and each [t] occurs exactly once in each calendar day. However, when
      daylight saving time begins or ends, some clock face times (and therefore [t]'s) can
      occur more than once per day or not at all, and e.g. 04:00 can occur three or five
      hours after midnight, so knowing your current offset from midnight is *not* in
      general equivalent to knowing the current [t].

      (See {!Zone} for tools to help you cope with DST.)

      There is one nonstandard representable value, [start_of_next_day], which can be
      thought of as "24:00:00" in 24-hour time. It is essentially "00:00:00" on the next
      day. By having this value, we allow comparisons against a strict upper bound on [t]
      values. However, it has some odd properties; for example, [Time.of_date_ofday ~zone
      date start_of_next_day |> Time.to_date ~zone] yields a different date.

      Any [ofday] will satisfy [start_of_day <= ofday <= start_of_next_day]. *)
  type underlying
  type t = private underlying [@@deriving bin_io, sexp]

  include Comparable_binable   with type t := t
  include Comparable.With_zero with type t := t
  include Hashable_binable     with type t := t
  include Pretty_printer.S     with type t := t
  include Robustly_comparable  with type t := t

  module Span : Span_intf.S

  (** [of_string] supports and correctly interprets 12h strings with the following suffixes:

      {v
      "A", "AM", "A.M.", "A.M"
      "P", "PM", "P.M.", "P.M"
    v}

      as well as the lowercase and space-prefixed versions of these suffixes.

      [of_string] also fully supports 24h wall-clock times.

      [to_string] only produces the 24h format. *)
  include Stringable with type t := t

  val create
    :  ?hr  : int
    -> ?min : int
    -> ?sec : int
    -> ?ms  : int
    -> ?us  : int
    -> ?ns  : int
    -> unit
    -> t

  val to_parts : t -> Span.Parts.t

  (** Smallest valid ofday. *)
  val start_of_day : t

  (** Largest representable ofday; see notes above on how [start_of_next_day] behaves
      differently from other ofday values. *)
  val start_of_next_day : t

  (** A time very close to the end of a day. Not necessarily the largest representable
      value before [start_of_next_day], but as close as possible such that using this
      ofday with [Time.of_date_ofday] and [Time.to_date] should round-trip to the same
      date. With floating-point representations of time, this may not be possible for
      dates extremely far from epoch.

      The clock-face time represented by [approximate_end_of_day] may vary with different
      time and ofday representations, depending on their precision. *)
  val approximate_end_of_day : t

  (** Note that these names are only really accurate on days without DST transitions. When
      clocks move forward or back, [of_span_since_start_of_day s] will not necessarily
      occur [s] after that day's midnight. *)
  val to_span_since_start_of_day : t -> Span.t
  val of_span_since_start_of_day : Span.t -> t

  (** [add t s] shifts the time of day [t] by the span [s].  It returns [None] if the
      result is not in the same 24-hour day. *)
  val add : t -> Span.t -> t option
  val sub : t -> Span.t -> t option

  (** [next t] return the next [t] (next t > t) or None if [t] = end of day. *)
  val next : t -> t option

  (** [prev t] return the previous [t] (prev t < t) or None if [t] = start of day. *)
  val prev : t -> t option

  (** [diff t1 t2] returns the difference in time between two ofdays, as if they occurred
      on the same 24-hour day. *)
  val diff : t -> t -> Span.t

  (** Returns the time-span separating the two of-days, ignoring the hour information, and
      assuming that the of-days represent times that are within a half-hour of each other.
      This is useful for comparing two ofdays in unknown time-zones. *)
  val small_diff : t -> t -> Span.t

  (** Trailing groups of zeroes are trimmed such that the output is printed in terms of
      the smallest non-zero units among nanoseconds, microseconds, milliseconds, or
      seconds; or minutes if all of the above are zero. *)
  val to_string_trimmed : t -> string

  (** HH:MM:SS, without any subsecond components. Seconds appear even if they are zero. *)
  val to_sec_string : t -> string

  val of_string_iso8601_extended : ?pos:int -> ?len:int -> string -> t

  (** with milliseconds *)
  val to_millisec_string : t -> string
end

module type S_stable = sig
  type t

  module V1 : sig
    type nonrec t = t [@@deriving bin_io, compare, hash, sexp]
  end
end

module type Ofday = sig
  include S

  module Stable : S_stable with type t := t
end
