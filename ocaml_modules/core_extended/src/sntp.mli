(** Simple Network Time Protocol *)

open! Core

(** [query hostname] returns the difference between the clock on the
  local host and the clock on the host specified by [hostname].

  If the remote host is down or not running an (S)NTP service this
  call will `Timeout.  Other errors, including some classes of resolution
  or network will raise an exception, which will be returned as `Error.
 *)
val query :
     ?timeout:Time.Span.t
  -> ?port:int
  -> string
  -> [ `Error of Exn.t | `Timeout | `Offset of Time.Span.t ]
;;

type t =
  { remote_host      : string
  ; offset           : Time.Span.t
  ; round_trip_delay : Time.Span.t
  ; stratum          : int
  ; root_delay       : Time.Span.t
  ; root_dispersion  : Time.Span.t
  ; t1               : float
  ; t2               : float
  ; t3               : float
  ; t4               : float }
[@@deriving sexp, fields]
;;

val extended_query :
  ?timeout:Time.Span.t
  -> ?port:int
  -> string
  -> t Or_error.t
;;
