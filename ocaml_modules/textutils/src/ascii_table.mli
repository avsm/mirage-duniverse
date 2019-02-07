open! Core

module Align : sig
  type t =
    | Left
    | Right
    | Center
end

module Display : sig
  type t
  val short_box     : t (* Default--cells can be multi-line.   *)
  val tall_box      : t (* Puts --- between entries.           *)
  val line          : t (* Trails off with ... if necessary.   *)
  val blank         : t (* No lines                            *)
  val column_titles : t (* Draw lines only under column titles *)
end

module Column : sig
  type 'a t

  (** creates a column given the header and the to-string function *)
  val create
    :  ?align : Align.t (* Default: left *)
    -> ?min_width : int
    -> ?max_width : int
    -> ?show : [ `Yes | `No | `If_not_empty ] (* Default: `Yes *)
    -> string
    -> ('a -> string)
    -> 'a t

  (** like create, except that the to_string function must provide a list of
      attributes. *)
  val create_attr:
    ?align : Align.t (* Default: left *)
    -> ?min_width : int
    -> ?max_width : int
    -> ?show : [ `Yes | `No | `If_not_empty ] (* Default: `Yes *)
    -> string
    -> ('a -> Console.Ansi.attr list * string)
    -> 'a t
end

type ('row, 'rest) renderer =
  ?display : Display.t (* Default: short_box *)
  -> ?spacing : int (* Default: 1 *)
  -> ?limit_width_to : int (* defaults to 90 characters *)
  -> ?header_attr : Console.Ansi.attr list
  -> ?bars : [ `Ascii | `Unicode ] (* defaults to [`Unicode] *)
  -> ?display_empty_rows : bool (* Default: false *)
  -> 'row Column.t list
  -> 'row list
  -> 'rest

(** The idea is that you have a Column.t list and a list of rows, where each
    row contains the data for each column.  So e.g. 'a could be a record type
    {col_1 : int; col_2 : string}, where the first column pulls out col_1 and
    the second column pulls out col_2. **)
val output : (_, oc:Out_channel.t -> unit) renderer

val to_string_noattr : (_, string) renderer
val to_string : (_, string) renderer

val simple_list_table : ?index:bool -> ?limit_width_to:int ->
  ?oc:Out_channel.t -> ?display:Display.t ->
  string list -> string list list -> unit

module Table_char : sig
  type t = {
    ascii : char;
    utf8 : string;
  }

  val connect : ?top:unit -> ?bottom:unit -> ?left:unit -> ?right:unit -> unit -> t
end
