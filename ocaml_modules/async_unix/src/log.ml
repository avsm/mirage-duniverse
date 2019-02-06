module Stable = struct
  open! Core.Core_stable

  module Level = struct
    module V1 = struct
      type t =
        [ `Debug
        | `Info
        | `Error
        ] [@@deriving bin_io, sexp]
    end
  end

  module Output = struct
    module Format = struct
      module V1 = struct
        type machine_readable = [`Sexp | `Sexp_hum | `Bin_prot ] [@@deriving sexp]
        type t = [ machine_readable | `Text ] [@@deriving sexp]
      end
    end
  end
end

open Core
open Import

module Scheduler = Raw_scheduler
module Sys       = Async_sys
module Unix      = Unix_syscalls

module Level = struct
  type t =
    [ `Debug
    | `Info
    | `Error
    ]
  [@@deriving bin_io, compare, sexp]

  let to_string = function
    | `Debug -> "Debug"
    | `Info  -> "Info"
    | `Error -> "Error"
  ;;

  let of_string = function
    | "Debug" -> `Debug
    | "Info"  -> `Info
    | "Error" -> `Error
    | s       -> failwithf "not a valid level %s" s ()

  let all = [`Debug; `Info; `Error]

  let arg =
    Command.Spec.Arg_type.of_alist_exn
      (List.concat_map all ~f:(fun t ->
         let s = to_string t in
         [ String.lowercase  s, t
         ; String.capitalize s, t
         ; String.uppercase  s, t ]))
  ;;

  (* Ordering of log levels in terms of verbosity. *)
  let as_or_more_verbose_than ~log_level ~msg_level =
    match msg_level with
    | None           -> true
    | Some msg_level ->
      begin match log_level, msg_level with
      | `Error, `Error           -> true
      | `Error, (`Debug | `Info) -> false
      | `Info,  (`Info | `Error) -> true
      | `Info, `Debug            -> false
      | `Debug, _                -> true
      end
  ;;

  module Stable = struct
    module V1 = Stable.Level.V1
  end
end

module Rotation = struct
  (* description of boundaries for file rotation.  If all fields are None the file will
     never be rotated.  Any field set to Some _ will cause rotation to happen when that
     boundary is crossed.  Multiple boundaries may be set.  Log rotation always causes
     incrementing rotation conditions (e.g. size) to reset, though this is the
     responsibililty of the caller to should_rotate.
  *)
  module V1 = struct
    type t =
      { messages      : int option
      ; size          : Byte_units.t option
      ; time          : (Time.Ofday.t * Time.Zone.t) option
      ; keep          : [ `All | `Newer_than of Time.Span.t | `At_least of int ]
      ; naming_scheme : [ `Numbered | `Timestamped ]
      }
    [@@deriving fields, sexp_of]
  end

  module V2 = struct
    type t =
      { messages      : int sexp_option
      ; size          : Byte_units.t sexp_option
      ; time          : Time.Ofday.t sexp_option
      ; keep          : [ `All | `Newer_than of Time.Span.t | `At_least of int ]
      ; naming_scheme : [ `Numbered | `Timestamped | `Dated ]
      ; zone          : Time.Zone.t [@default (force Time.Zone.local)]
      }
    [@@deriving fields, sexp]
  end

  module type Id_intf = sig
    type t
    val create : Time.Zone.t -> t
    (* For any rotation scheme that renames logs on rotation, this defines how to do
       the renaming. *)
    val rotate_one : t -> t

    val to_string_opt : t -> string option
    val of_string_opt : string option -> t option
    val cmp_newest_first : t -> t -> int
  end

  module V3 = struct

    type naming_scheme = [ `Numbered | `Timestamped | `Dated | `User_defined of (module Id_intf) ]

    type t =
      { messages      : int sexp_option
      ; size          : Byte_units.t sexp_option
      ; time          : Time.Ofday.t sexp_option
      ; keep          : [ `All | `Newer_than of Time.Span.t | `At_least of int ]
      ; naming_scheme : naming_scheme
      ; zone          : Time.Zone.t
      }
    [@@deriving fields]

    let sexp_of_t t =
      let a x = Sexp.Atom x and l x = Sexp.List x in
      let o x name sexp_of =
        Option.map x ~f:(fun x -> (l [a name; sexp_of x]))
      in
      let messages = o t.messages "messages" Int.sexp_of_t in
      let size = o t.size "size" Byte_units.sexp_of_t in
      let time = o t.time "time" Time.Ofday.sexp_of_t in
      let keep =
        l [a "keep";
           match t.keep with
           | `All -> a "All"
           | `Newer_than span -> l [a "Newer_than"; Time.Span.sexp_of_t span]
           | `At_least n -> l [a "At_least"; Int.sexp_of_t n]]
      in
      let naming_scheme =
        l [a "naming_scheme";
           match t.naming_scheme with
           | `Numbered       -> a "Numbered"
           | `Timestamped    -> a "Timestamped"
           | `Dated          -> a "Dated"
           | `User_defined _ -> a "User_defined"]
      in
      let zone = l [a "zone"; Time.Zone.sexp_of_t t.zone] in
      let all = List.filter_map ~f:Fn.id [messages; size; time; Some keep; Some naming_scheme; Some zone] in
      l all

  end

  include V3

  let create ?messages ?size ?time ?zone ~keep ~naming_scheme () =
    { messages
    ; size
    ; time
    ; zone          = Option.value zone ~default:(force Time.Zone.local)
    ; keep
    ; naming_scheme
    }

  let sexp_of_t = V3.sexp_of_t

  let first_occurrence_after time ~ofday ~zone =
    let first_at_or_after time = Time.occurrence `First_after_or_at time ~ofday ~zone in
    let candidate = first_at_or_after time in
    (* we take care not to return the same time we were given *)
    if Time.equal time candidate
    then (first_at_or_after (Time.add time Time.Span.robust_comparison_tolerance))
    else candidate
  ;;

  let should_rotate t ~last_messages ~last_size ~last_time ~current_time =
    Fields.fold ~init:false
      ~messages:(fun acc field ->
        match Field.get field t with
        | None -> acc
        | Some rotate_messages -> acc || rotate_messages <= last_messages)
      ~size:(fun acc field ->
        match Field.get field t with
        | None -> acc
        | Some rotate_size -> acc || Byte_units.(<=) rotate_size last_size)
      ~time:(fun acc field ->
        match Field.get field t with
        | None -> acc
        | Some rotation_ofday ->
          let rotation_time =
            first_occurrence_after last_time ~ofday:rotation_ofday ~zone:t.zone
          in
          acc || Time.( >= ) current_time rotation_time)
      ~zone:(fun acc _ -> acc)
      ~keep:(fun acc _ -> acc)
      ~naming_scheme:(fun acc _ -> acc)
  ;;

  let default ?(zone = (force Time.Zone.local)) () =
    { messages      = None
    ; size          = None
    ; time          = Some Time.Ofday.start_of_day
    ; keep          = `All
    ; naming_scheme = `Dated
    ; zone
    }
end

module Sexp_or_string = struct
  type t =
    [ `Sexp   of Sexp.t
    | `String of string
    ]
  [@@deriving bin_io, sexp]

  let to_string = function
    | `Sexp sexp  -> Sexp.to_string sexp
    | `String str -> str
  ;;
end

module Message : sig
  type t [@@deriving bin_io, sexp]

  val create
    :  ?level:Level.t
    -> ?time:Time.t
    -> ?tags:(string * string) list
    -> Sexp_or_string.t
    -> t

  val time        : t -> Time.t
  val level       : t -> Level.t option
  val set_level   : t -> Level.t option -> t
  val message     : t -> string
  val raw_message : t -> [ `String of string | `Sexp of Sexp.t ]
  val tags        : t -> (string * string) list
  val add_tags    : t -> (string * string) list -> t

  val to_write_only_text : ?zone:Time.Zone.t -> t -> string

  val write_write_only_text : t -> Writer.t -> unit
  val write_sexp            : t -> hum:bool -> Writer.t -> unit
  val write_bin_prot        : t -> Writer.t -> unit

  module Stable : sig
    module V0 : sig
      type nonrec t = t [@@deriving bin_io, sexp]
    end

    module V2 : sig
      type nonrec t = t [@@deriving bin_io, sexp]
    end
  end
end = struct
  module T = struct
    type 'a t =
      { time    : Time.t
      ; level   : Level.t option
      ; message : 'a
      ; tags    : (string * string) list
      }
    [@@deriving bin_io, sexp]

    let (=) t1 t2 =
      let compare_tags =
        Tuple.T2.compare ~cmp1:String.compare ~cmp2:String.compare
      in
      Time.(=.) t1.time t2.time
      && [%compare.equal: Level.t option] t1.level t2.level
      && Poly.equal t1.message t2.message
      (* The same key can appear more than once in tags, and order shouldn't matter
         when comparing *)
      && List.compare [%compare: String.t * String.t]
           (List.sort ~compare:compare_tags t1.tags) (List.sort ~compare:compare_tags t2.tags)
         = 0
    ;;

    let%test_unit _ =
      let time    = Time.now () in
      let level   = Some `Info in
      let message = "test unordered tags" in
      let t1 = { time; level; message; tags = [ "a", "a1"; "a", "a2"; "b", "b1" ] } in
      let t2 = { time; level; message; tags = [ "a", "a2"; "a", "a1"; "b", "b1" ] } in
      let t3 = { time; level; message; tags = [ "a", "a2"; "b", "b1"; "a", "a1" ] } in
      assert (t1 = t2);
      assert (t2 = t3)
    ;;
  end
  open T

  (* Log messages are stored, starting with V2, as an explicit version followed by the
     message itself.  This makes it easier to move the message format forward while
     still allowing older logs to be read by the new code.

     If you make a new version you must add a version to the Version module below and
     should follow the Make_versioned_serializable pattern.
  *)
  module Stable = struct
    module Version = struct
      type t =
        | V2
      [@@deriving bin_io, sexp, compare]

      let (<>) t1 t2 = compare t1 t2 <> 0
      let to_string t = Sexp.to_string (sexp_of_t t)
    end

    module type Versioned_serializable = sig
      type t [@@deriving bin_io, sexp]

      val version : Version.t
    end

    module Make_versioned_serializable(T : Versioned_serializable) : sig
      type t [@@deriving bin_io, sexp]
    end with type t = T.t = struct
      type t = T.t
      type versioned_serializable = Version.t * T.t [@@deriving bin_io, sexp]

      let t_of_versioned_serializable (version, t) =
        if Version.(<>) version T.version
        then (
          failwithf !"version mismatch %{Version} <> to expected version %{Version}"
            version T.version ())
        else t
      ;;

      let sexp_of_t t =
        sexp_of_versioned_serializable (T.version, t)
      ;;

      let t_of_sexp sexp =
        let versioned_t = versioned_serializable_of_sexp sexp in
        t_of_versioned_serializable versioned_t
      ;;

      include
        Binable.Stable.Of_binable.V1
          (struct type t = versioned_serializable [@@deriving bin_io] end)
          (struct
            type t = T.t
            let to_binable t           = (T.version, t)
            let of_binable versioned_t = t_of_versioned_serializable versioned_t
          end)
    end

    module V2 = Make_versioned_serializable (struct
        type nonrec t = Sexp_or_string.t t [@@deriving bin_io, sexp]

        let version = Version.V2
      end)

    (* this is the serialization scheme in 111.18 and before *)
    module V0 = struct
      type v0_t = string T.t [@@deriving bin_io, sexp]

      let v0_to_v2 (v0_t : v0_t) : V2.t =
        {
          time    = v0_t.time;
          level   = v0_t.level;
          message = `String v0_t.message;
          tags    = v0_t.tags;
        }

      let v2_to_v0 (v2_t : V2.t) : v0_t =
        { time    = v2_t.time
        ; level   = v2_t.level
        ; message = Sexp_or_string.to_string v2_t.message
        ; tags    = v2_t.tags
        }

      include Binable.Stable.Of_binable.V1
          (struct type t = v0_t [@@deriving bin_io] end)
          (struct
            let to_binable = v2_to_v0
            let of_binable = v0_to_v2
            type t = Sexp_or_string.t T.t
          end)

      let sexp_of_t t    = sexp_of_v0_t (v2_to_v0 t)
      let t_of_sexp sexp = v0_to_v2 (v0_t_of_sexp sexp)

      type t = V2.t
    end
  end

  include Stable.V2

  (* this allows for automagical reading of any versioned sexp, so long as we can always
     lift to a Message.t *)
  let t_of_sexp (sexp : Sexp.t) =
    match sexp with
    | List (List (Atom "time" :: _) :: _) ->
      Stable.V0.t_of_sexp sexp
    | List [ (Atom _) as version; _ ] ->
      begin match Stable.Version.t_of_sexp version with
      | V2 -> Stable.V2.t_of_sexp sexp
      end
    | _ -> failwithf !"Log.Message.t_of_sexp: malformed sexp: %{Sexp}" sexp ()
  ;;

  let create
        ?level
        ?(time  = (Time.now ()))
        ?(tags  = [])
        message =
    { time; level; message; tags }
  ;;

  let%test_unit _ =
    let msg =
      create ~level:`Info ~tags:["a", "tag"]
        (`String "the quick brown message jumped over the lazy log")
    in
    let v0_sexp = Stable.V0.sexp_of_t msg in
    let v2_sexp = Stable.V2.sexp_of_t msg in
    assert (t_of_sexp v0_sexp = msg);
    assert (t_of_sexp v2_sexp = msg)
  ;;

  let%test_unit _ =
    let msg =
      create ~level:`Info ~tags:["a", "tag"]
        (`Sexp (Sexp.List [ Atom "foo"; Atom "bar" ]))
    in
    let v0_sexp = Stable.V0.sexp_of_t msg in
    let v2_sexp = Stable.V2.sexp_of_t msg in
    assert (t_of_sexp v0_sexp = { msg with message = `String "(foo bar)" });
    assert (t_of_sexp v2_sexp = msg)
  ;;

  let%test_unit _ =
    let msg = create ~level:`Info ~tags:[] (`String "") in
    match sexp_of_t msg with
    | List [ (Atom _) as version; _ ] ->
      ignore (Stable.Version.t_of_sexp version : Stable.Version.t)
    | _ -> assert false
  ;;

  let time t    = t.time
  let level t   = t.level

  let set_level t level = { t with level }

  let raw_message t = t.message

  let message t = Sexp_or_string.to_string (raw_message t)

  let tags t    = t.tags

  let add_tags t tags = {t with tags = List.rev_append tags t.tags}

  let to_write_only_text ?(zone=(force Time.Zone.local)) t =
    let prefix =
      match t.level with
      | None   -> ""
      | Some l -> Level.to_string l ^ " "
    in
    let formatted_tags =
      match t.tags with
      | [] -> []
      | _ :: _ ->
        " --"
        :: List.concat_map t.tags ~f:(fun (t, v) ->
          [" ["; t; ": "; v; "]"])
    in
    String.concat ~sep:"" (
      Time.to_string_abs ~zone t.time
      :: " "
      :: prefix
      :: message t
      :: formatted_tags)
  ;;

  let%test_unit _ =
    let check expect t =
      let zone = Time.Zone.utc in
      [%test_result: string] (to_write_only_text ~zone t) ~expect
    in
    check "2013-12-13 15:00:00.000000Z <message>"
      { time    = Time.of_string "2013-12-13 15:00:00Z"
      ; level   = None
      ; tags    = []
      ; message = `String "<message>"
      };
    check "2013-12-13 15:00:00.000000Z Info <message>"
      { time    = Time.of_string "2013-12-13 15:00:00Z"
      ; level   = Some `Info
      ; tags    = []
      ; message = `String "<message>"
      };
    check "2013-12-13 15:00:00.000000Z Info <message> -- [k1: v1] [k2: v2]"
      { time    = Time.of_string "2013-12-13 15:00:00Z"
      ; level   = Some `Info
      ; tags    = ["k1", "v1"; "k2", "v2"]
      ; message = `String "<message>"
      }
  ;;

  let write_write_only_text t wr =
    Writer.write wr (to_write_only_text t);
    Writer.newline wr
  ;;

  let write_sexp t ~hum wr =
    Writer.write_sexp ~hum wr (sexp_of_t t);
    Writer.newline wr
  ;;

  let write_bin_prot t wr =
    Writer.write_bin_prot wr bin_writer_t t
  ;;
end

module Output : sig
  (* The output module exposes a variant that describes the output type and sub-modules
     that each expose a write function (or create that returns a write function) that is
     of type: Level.t -> string -> unit Deferred.t.  It is the responsibility of the write
     function to contain all state, and to clean up after itself.
  *)
  module Format : sig
    type machine_readable = [`Sexp | `Sexp_hum | `Bin_prot ] [@@deriving sexp]
    type t = [ machine_readable | `Text ] [@@deriving sexp]

    module Stable : sig
      module V1 : sig
        type nonrec t = t [@@deriving sexp]
      end
    end
  end

  type t [@@deriving sexp_of]

  val create
    :  ?rotate:(unit -> unit Deferred.t)
    -> ?close:(unit -> unit Deferred.t)
    -> flush:(unit -> unit Deferred.t)
    -> (Message.t Queue.t -> unit Deferred.t)
    -> t

  val write  : t -> Message.t Queue.t -> unit Deferred.t
  val rotate : t -> unit Deferred.t
  val flush  : t -> unit Deferred.t

  val stdout        : unit -> t
  val stderr        : unit -> t
  val writer        : Format.t -> Writer.t -> t
  val file          : Format.t -> filename:string -> t
  val rotating_file : Format.t -> basename:string -> Rotation.t -> t

  val rotating_file_with_tail : Format.t -> basename:string -> Rotation.t -> t * string Tail.t

  val combine : t list -> t
end = struct
  module Format = struct
    type machine_readable = [`Sexp | `Sexp_hum | `Bin_prot ] [@@deriving sexp]
    type t = [ machine_readable | `Text ] [@@deriving sexp]

    module Stable = struct
      module V1 = Stable.Output.Format.V1
    end
  end

  module Definitely_a_heap_block : sig
    type t

    val the_one_and_only : t
  end = struct
    type t = string

    let the_one_and_only = String.make 1 ' '
  end

  type t =
    { write      : Message.t Queue.t -> unit Deferred.t
    ; rotate     : (unit -> unit Deferred.t)
    ; close      : (unit -> unit Deferred.t)
    ; flush      : (unit -> unit Deferred.t)
    (* experimentation shows that this record, without this field, can sometimes raise
       when passed to Heap_block.create_exn, which we need to do to add a finalizer.  This
       seems to occur when the functions are top-level and/or constant.  More
       investigation is probably worthwhile. *)
    ; heap_block : Definitely_a_heap_block.t
    }

  let create
        ?(rotate = (fun () -> return ()))
        ?(close = (fun () -> return ()))
        ~flush
        write
    =
    let t =
      { write
      ; rotate
      ; close
      ; flush
      ; heap_block = Definitely_a_heap_block.the_one_and_only }
    in
    Gc.add_finalizer (Heap_block.create_exn t) (fun t ->
      let t = Heap_block.value t in
      don't_wait_for
        (let%bind () = t.flush () in
         t.close ()));
    t
  ;;

  let write t msgs = t.write msgs
  let rotate t     = t.rotate ()
  let flush t      = t.flush ()

  let sexp_of_t _ = Sexp.Atom "<opaque>"

  let combine ts =
    (* There is a crazy test that verifies that we combine things correctly when the same
       rotate output is included 5 times in Log.create, so we must make this Sequential to
       enforce the rotate invariants and behavior. *)
    let iter_combine_exns =
      (* No need for the Monitor overhead in the case of a single t *)
      match ts with
      | [single_t] -> (fun f -> f single_t)
      | ts ->
        (fun f ->
           Deferred.List.map ~how:`Sequential ts
             ~f:(fun t -> Monitor.try_with_or_error (fun () -> f t))
           >>| Or_error.combine_errors_unit
           >>| Or_error.ok_exn)
    in
    let write  = (fun msg -> iter_combine_exns (fun t -> t.write msg)) in
    let rotate = (fun ()  -> iter_combine_exns (fun t -> t.rotate ())) in
    let close  = (fun ()  -> iter_combine_exns (fun t -> t.close  ())) in
    let flush  = (fun ()  -> iter_combine_exns (fun t -> t.flush  ())) in
    { write; rotate; close; flush; heap_block = Definitely_a_heap_block.the_one_and_only }
  ;;

  let basic_write format w msg =
    begin match format with
    | `Sexp ->
      Message.write_sexp msg ~hum:false w
    | `Sexp_hum ->
      Message.write_sexp msg ~hum:true w
    | `Bin_prot ->
      Message.write_bin_prot msg w
    | `Text ->
      Message.write_write_only_text msg w
    end;
  ;;

  let open_file filename =
    (* guard the open_file with a unit deferred to prevent any work from happening
       before async spins up.  Without this no real work will be done, but async will be
       initialized, which will raise if we later call Scheduler.go_main. *)
    return ()
    >>= fun () ->
    Writer.open_file ~append:true filename
  ;;

  let open_writer ~filename =
    (* the lazy pushes evaluation to the first place we use it, which keeps writer
       creation errors within the error handlers for the log. *)
    lazy begin
      open_file filename
      >>| fun w ->
      (* if we are writing to a slow device, or a temporarily disconnected
         device it's better to push back on memory in the hopes that the
         disconnection will resolve than to blow up after a timeout.  If
         we had a better logging error reporting mechanism we could
         potentially deal with it that way, but we currently don't. *)
      Writer.set_buffer_age_limit w `Unlimited;
      w
    end
  ;;

  let write_immediately w format msgs =
    Queue.iter msgs ~f:(fun msg -> basic_write format w msg);
    Writer.bytes_received w
  ;;

  let write' w format msgs =
    let%map w = w in
    write_immediately w format msgs
  ;;

  module File : sig
    val create : Format.t -> filename:string -> t
  end = struct
    let create format ~filename =
      let w = open_writer ~filename in
      create
        ~close:(fun () ->
          if Lazy.is_val w
          then (force w >>= Writer.close)
          else (return ()))
        ~flush:(fun () ->
          if Lazy.is_val w
          then (force w >>= Writer.flushed)
          else (return ()))
        (fun msgs ->
           let%map (_ : Int63.t) = write' (force w) format msgs in
           ())
    ;;
  end

  module Log_writer : sig
    val create : Format.t -> Writer.t -> t
  end = struct
    (* The writer output type takes no responsibility over the Writer.t it is given.  In
       particular it makes no attempt to ever close it. *)
    let create format w =
      create
        ~flush:(fun () -> Writer.flushed w)
        (fun msgs ->
           Queue.iter msgs ~f:(fun msg -> basic_write format w msg);
           return ())
  end

  module Rotating_file : sig
    val create
      :  Format.t
      -> basename:string
      -> Rotation.t
      -> t * string Tail.t
  end = struct
    module Make (Id:Rotation.Id_intf) = struct
      let make_filename ~dirname ~basename id =
        match Id.to_string_opt id with
        | None   -> dirname ^/ sprintf "%s.log" basename
        | Some s -> dirname ^/ sprintf "%s.%s.log" basename s
      ;;

      let parse_filename_id ~basename filename =
        if String.equal (Filename.basename filename) (basename ^ ".log")
        then (Id.of_string_opt None)
        else begin
          let open Option.Monad_infix in
          String.chop_prefix (Filename.basename filename) ~prefix:(basename ^ ".")
          >>= fun id_dot_log ->
          String.chop_suffix id_dot_log ~suffix:".log"
          >>= fun id ->
          Id.of_string_opt (Some id)
        end
      ;;

      let current_log_files ~dirname ~basename =
        Sys.readdir dirname
        >>| fun files ->
        List.filter_map (Array.to_list files) ~f:(fun filename ->
          let filename = dirname ^/ filename in
          Option.(parse_filename_id ~basename filename >>| fun id -> id, filename))
      ;;

      (* errors from this function should be ignored.  If this function fails to run, the
         disk may fill up with old logs, but external monitoring should catch that, and
         the core function of the Log module will be unaffected. *)
      let maybe_delete_old_logs ~dirname ~basename keep =
        begin match keep with
        | `All -> return []
        | `Newer_than span ->
          current_log_files ~dirname ~basename
          >>= fun files ->
          let cutoff = Time.sub (Time.now ()) span in
          Deferred.List.filter files ~f:(fun (_, filename) ->
            Deferred.Or_error.try_with (fun () -> Unix.stat filename)
            >>| function
            | Error _ -> false
            | Ok stats -> Time.(<) stats.mtime cutoff)
        | `At_least i ->
          current_log_files ~dirname ~basename
          >>| fun files ->
          let files =
            List.sort files ~compare:(fun (i1,_) (i2,_) -> Id.cmp_newest_first i1 i2)
          in
          List.drop files i
        end
        >>= Deferred.List.map ~f:(fun (_i,filename) ->
          Deferred.Or_error.try_with (fun () -> Unix.unlink filename))
        >>| fun (_ : unit Or_error.t list) -> ()
      ;;

      type t =
        {         basename      : string
        ;         dirname       : string
        ;         rotation      : Rotation.t
        ;         format        : Format.t
        ; mutable writer        : Writer.t Deferred.t Lazy.t
        ; mutable filename      : string
        ; mutable last_messages : int
        ; mutable last_size     : int
        ; mutable last_time     : Time.t
        ; log_files             : string Tail.t
        }
      [@@deriving sexp_of]

      let we_have_written_to_the_current_writer t = Lazy.is_val t.writer

      let close_writer t =
        if we_have_written_to_the_current_writer t
        then begin
          let%bind w = Lazy.force t.writer in
          Writer.close w
        end else (return ())
      ;;

      let rotate t =
        let basename, dirname = t.basename, t.dirname in
        close_writer t
        >>= fun () ->
        current_log_files ~dirname ~basename
        >>= fun files ->
        let files =
          List.rev (List.sort files ~compare:(fun (i1,_) (i2, _) -> Id.cmp_newest_first i1 i2))
        in
        Deferred.List.iter files ~f:(fun (id, src) ->
          let id' = Id.rotate_one id in
          let dst = make_filename ~dirname ~basename id' in
          if String.equal src t.filename then (Tail.extend t.log_files dst);
          if Id.cmp_newest_first id id' <> 0
          then (Unix.rename ~src ~dst)
          else (return ()))
        >>= fun () ->
        maybe_delete_old_logs ~dirname ~basename t.rotation.keep
        >>| fun () ->
        let filename =
          make_filename ~dirname ~basename (Id.create (Rotation.zone t.rotation))
        in
        t.last_size     <- 0;
        t.last_messages <- 0;
        t.last_time     <- Time.now ();
        t.filename      <- filename;
        t.writer        <- open_writer ~filename;
      ;;

      let write t msgs =
        let current_time = Time.now () in
        begin
          if Rotation.should_rotate
               t.rotation
               ~last_messages:t.last_messages
               ~last_size:(Byte_units.create `Bytes (Float.of_int t.last_size))
               ~last_time:t.last_time
               ~current_time
          then (rotate t)
          else (return ())
        end >>= fun () ->
        write' (Lazy.force t.writer) t.format msgs
        >>| fun size ->
        t.last_messages <- t.last_messages + Queue.length msgs;
        t.last_size     <- Int63.to_int_exn size;
        t.last_time     <- current_time;
      ;;

      let create format ~basename rotation =
        let basename, dirname =
          (* make dirname absolute, because cwd may change *)
          match Filename.is_absolute basename with
          | true  -> Filename.basename basename, return (Filename.dirname basename)
          | false -> basename, Sys.getcwd ()
        in
        let log_files = Tail.create () in
        let t_deferred =
          dirname
          >>| fun dirname ->
          let filename =
            make_filename ~dirname ~basename (Id.create (Rotation.zone rotation))
          in
          { basename
          ; dirname
          ; rotation
          ; format
          ; writer        = open_writer ~filename
          ; filename
          ; last_size     = 0
          ; last_messages = 0
          ; last_time     = Time.now ()
          ; log_files
          }
        in
        let first_rotate_scheduled = ref false in
        let close () =
          let%bind t = t_deferred in
          close_writer t
        in
        let flush () =
          let%bind t = t_deferred in
          if Lazy.is_val t.writer
          then (force t.writer >>= Writer.flushed)
          else (return ())
        in
        create
          ~close
          ~flush
          ~rotate:(fun () -> t_deferred >>= rotate)
          (fun msgs ->
             t_deferred
             >>= fun t ->
             if not !first_rotate_scheduled then begin
               first_rotate_scheduled := true;
               rotate t
               >>= fun () ->
               write t msgs
             end else
               (write t msgs)), log_files
      ;;
    end

    module Numbered = Make (struct
        type t = int

        let create           = const 0
        let rotate_one       = (+) 1
        let to_string_opt    = function 0 -> None | x -> Some (Int.to_string x)
        let cmp_newest_first = Int.ascending

        let of_string_opt = function
          | None   -> Some 0
          | Some s -> try Some (Int.of_string s) with _ -> None
        ;;
      end)

    module Timestamped = Make (struct
        type t = Time.t

        let create _zone     = Time.now ()
        let rotate_one       = ident
        let to_string_opt ts = Some (Time.to_filename_string ~zone:(force Time.Zone.local) ts)
        let cmp_newest_first = Time.descending

        let of_string_opt = function
          | None   -> None
          | Some s -> try Some (Time.of_filename_string ~zone:(force Time.Zone.local) s) with _ -> None
        ;;
      end)

    module Dated = Make (struct
        type t = Date.t

        let create zone        = Date.today ~zone
        let rotate_one         = ident
        let to_string_opt date = Some (Date.to_string date)
        let cmp_newest_first   = Date.descending

        let of_string_opt = function
          | None     -> None
          | Some str -> Option.try_with (fun () -> Date.of_string str)
        ;;
      end)

    let create format ~basename (rotation : Rotation.t) =
      match rotation.naming_scheme with
      | `Numbered    -> Numbered.create format ~basename rotation
      | `Timestamped -> Timestamped.create format ~basename rotation
      | `Dated       -> Dated.create format ~basename rotation
      | `User_defined id ->
        let module Id = (val id : Rotation.Id_intf) in
        let module User_defined = Make (Id) in
        User_defined.create format ~basename rotation
    ;;
  end

  let rotating_file format ~basename rotation = fst (Rotating_file.create format ~basename rotation)
  let rotating_file_with_tail = Rotating_file.create
  let file          = File.create
  let writer        = Log_writer.create

  let stdout = Memo.unit (fun () -> Log_writer.create `Text (Lazy.force Writer.stdout))
  let stderr = Memo.unit (fun () -> Log_writer.create `Text (Lazy.force Writer.stderr))
end

(* A log is a pipe that can take one of four messages.
   | Msg (level, msg) -> write the message to the current output if the level is
   appropriate
   | New_output f -> set the output function for future messages to f
   | Flush i      -> used to get around the current odd design of Pipe flushing.  Sends an
   ivar that the reading side fills in after it has finished handling
   all previous messages.
   | Rotate  -> inform the output handlers to rotate exactly now

   The f delivered by New_output must not hold on to any resources that normal garbage
   collection won't clean up.  When New_output is delivered to the pipe the current
   write function will be discarded without notification.  If this proves to be a
   resource problem (too many syscalls for instance) then we could add an on_discard
   function to writers that we call when a new writer appears.
*)
module Update = struct
  type t =
    | Msg        of Message.Stable.V2.t
    | New_output of Output.t
    | Flush      of unit Ivar.t
    | Rotate     of unit Ivar.t
  [@@deriving sexp_of]

  let to_string t = Sexp.to_string (sexp_of_t t)
end

type t =
  { updates                    : Update.t Pipe.Writer.t
  ; mutable on_error           : [ `Raise | `Call of (Error.t -> unit) ]
  ; mutable current_level      : Level.t
  ; mutable output_is_disabled : bool
  ; mutable current_output     : Output.t list
  }

let equal t1 t2 = Pipe.equal t1.updates t2.updates
let hash t = Pipe.hash t.updates

let sexp_of_t _t = Sexp.Atom "<opaque>"

let push_update t update =
  if not (Pipe.is_closed t.updates)
  then (Pipe.write_without_pushback t.updates update)
  else (
    failwithf "Log: can't process %s because this log has been closed"
      (Update.to_string update) ())
;;

let flushed t = Deferred.create (fun i -> push_update t (Flush i))

let rotate t = Deferred.create (fun i -> push_update t (Rotate i))

let is_closed t = Pipe.is_closed t.updates

module Flush_at_exit_or_gc : sig
  val add_log : t -> unit
  val close   : t -> unit Deferred.t
end = struct
  module Weak_table = Caml.Weak.Make (struct
      type z = t
      type t = z
      let equal = equal
      let hash  = hash
    end)

  (* contains all logs we want to flush at shutdown *)
  let flush_bag = lazy (Bag.create ())

  (* contains all currently live logs. *)
  let live_logs = lazy (Weak_table.create 1)

  (* [flush] adds a flush deferred to the flush_bag *)
  let flush t =
    if not (is_closed t) then begin
      let flush_bag = Lazy.force flush_bag in
      let flushed   = flushed t in
      let tag       = Bag.add flush_bag flushed in
      upon flushed (fun () -> Bag.remove flush_bag tag);
      flushed
    end else
      (return ())
  ;;

  let close t =
    if not (is_closed t)
    then begin
      (* this will cause the log to flush its outputs, but because they may have been
         reused it does not close them, they'll be closed automatically when they fall out
         of scope. *)
      Pipe.write_without_pushback t.updates (New_output (Output.combine []));
      let finished = flushed t in
      Pipe.close t.updates;
      finished
    end else
      (return ())
  ;;

  let finish_at_shutdown =
    lazy
      (Shutdown.at_shutdown (fun () ->
         let live_logs = Lazy.force live_logs in
         let flush_bag = Lazy.force flush_bag in
         Weak_table.iter (fun log -> don't_wait_for (flush log)) live_logs;
         Deferred.all_unit (Bag.to_list flush_bag)))
  ;;

  let add_log log =
    let live_logs = Lazy.force live_logs in
    Lazy.force finish_at_shutdown;
    Weak_table.remove live_logs log;
    Weak_table.add live_logs log;
    (* If we fall out of scope just close and flush normally.  Without this we risk being
       finalized and removed from the weak table before the the shutdown handler runs, but
       also before we get all of logs out of the door. *)
    Gc.add_finalizer_exn log (fun log -> don't_wait_for (close log));
  ;;
end

let close = Flush_at_exit_or_gc.close

let create_log_processor ~output =
  let batch_size             = 100 in
  let output                 = ref (Output.combine output) in
  let msgs                   = Queue.create () in
  let output_message_queue f =
    if Queue.length msgs = 0
    then (f ())
    else begin
      Output.write !output msgs
      >>= fun () ->
      Queue.clear msgs;
      f ()
    end
  in
  (fun (updates : Update.t Queue.t) ->
     let rec loop yield_every =
       let yield_every = yield_every - 1 in
       if yield_every = 0
       then begin
         (* this introduces a yield point so that other async jobs have a chance to run
            under circumstances when large batches of logs are delivered in bursts. *)
         Scheduler.yield ()
         >>= fun () ->
         loop batch_size
       end else begin
         match Queue.dequeue updates with
         | None -> output_message_queue (fun _ -> return ())
         | Some update ->
           begin match update with
           | Rotate i ->
             output_message_queue (fun () ->
               Output.rotate !output
               >>= fun () ->
               Ivar.fill i ();
               loop yield_every)
           | Flush i ->
             output_message_queue (fun () ->
               Output.flush !output
               >>= fun () ->
               Ivar.fill i ();
               loop yield_every)
           | Msg msg ->
             Queue.enqueue msgs msg;
             loop yield_every
           | New_output o ->
             output_message_queue (fun () ->
               (* we don't close the output because we may re-use it.  We rely on the
                  finalizer on the output to call close once it falls out of scope. *)
               Output.flush !output
               >>= fun () ->
               output := o;
               loop yield_every)
           end
       end
     in
     loop batch_size)
;;

let process_log_redirecting_all_errors t r output =
  Monitor.try_with (fun () ->
    let process_log = create_log_processor ~output in
    Pipe.iter' r ~f:process_log)
  >>| function
  | Ok ()   -> ()
  | Error e ->
    begin match t.on_error with
    | `Raise  -> raise e
    | `Call f -> f (Error.of_exn e)
    end
;;

let create ~level ~output ~on_error : t =
  let r,w = Pipe.create () in
  let t =
    { updates            = w
    ; on_error
    ; current_level      = level
    ; output_is_disabled = List.is_empty output
    ; current_output     = output
    }
  in
  Flush_at_exit_or_gc.add_log t;
  don't_wait_for (process_log_redirecting_all_errors t r output);
  t
;;

let set_output t outputs =
  t.output_is_disabled <- List.is_empty outputs;
  t.current_output <- outputs;
  push_update t (New_output (Output.combine outputs))
;;

let get_output t = t.current_output

let set_on_error t handler = t.on_error <- handler

let level t = t.current_level

let set_level t level =
  t.current_level <- level
;;

let%test_unit "Level setting" =
  let assert_log_level log expected_level =
    match (level log, expected_level) with
    | `Info, `Info
    | `Debug, `Debug
    | `Error, `Error -> Ok ()
    | actual_level, expected_level ->
      Or_error.errorf "Expected %S but got %S"
        (Level.to_string expected_level) (Level.to_string actual_level)
  in
  let answer =
    let open Or_error.Monad_infix in
    let initial_level = `Debug in
    let output = [Output.create ~flush:(fun () -> return ()) (fun _ -> return ())] in
    let log = create ~level:initial_level ~output ~on_error:`Raise in
    assert_log_level log initial_level
    >>= fun () ->
    set_level log `Info;
    assert_log_level log `Info
    >>= fun () ->
    set_level log `Debug;
    set_level log `Error;
    assert_log_level log `Error
  in
  Or_error.ok_exn answer
;;

(* would_log is broken out and tested separately for every sending function to avoid the
   overhead of message allocation when we are just going to drop the message. *)
let would_log t msg_level =
  not t.output_is_disabled
  && Level.as_or_more_verbose_than ~log_level:(level t) ~msg_level

let message t msg =
  if would_log t (Message.level msg)
  then (push_update t (Msg msg))

let sexp ?level ?time ?tags t sexp =
  if would_log t level
  then (push_update t (Msg (Message.create ?level ?time ?tags (`Sexp sexp))))
;;

let string ?level ?time ?tags t s =
  if would_log t level
  then (push_update t (Msg (Message.create ?level ?time ?tags (`String s))))
;;

let printf ?level ?time ?tags t fmt =
  if would_log t level then begin
    ksprintf
      (fun msg -> push_update t (Msg (Message.create ?level ?time ?tags (`String msg))))
      fmt
  end else begin
    ifprintf () fmt
  end
;;

let add_uuid_to_tags tags =
  let uuid =
    if Ppx_inline_test_lib.Runtime.testing
    then Uuid.Stable.V1.for_testing
    else (Uuid.create ())
  in
  ("Log.surround_id", Uuid.to_string uuid) :: tags
;;

let surround_s_gen
      ?(tags=[])
      ~try_with
      ~map_return
      ~(log_sexp : ?tags:(string * string) list -> Sexp.t -> unit)
      ~f
      msg
  =
  let tags = add_uuid_to_tags tags in
  log_sexp ~tags [%message "Enter" ~_:(msg : Sexp.t) ];
  map_return (try_with f) ~f:(function
    | Ok x ->
      log_sexp ~tags [%message "Exit" ~_:(msg : Sexp.t)];
      x
    | Error exn ->
      log_sexp ~tags [%message "Raised while " ~_:(msg : Sexp.t) (exn : exn)];
      Exn.reraise exn (sprintf !"%{sexp:Sexp.t}" msg))
;;

let surroundf_gen
      ?(tags=[])
      ~try_with
      ~map_return
      ~(log_string:(?tags:(string*string) list -> string -> unit))
  =
  ksprintf (fun msg f ->
    let tags = add_uuid_to_tags tags in
    log_string ~tags ("Enter " ^ msg);
    map_return (try_with f) ~f:(function
      | Ok x ->
        log_string ~tags ("Exit " ^ msg);
        x
      | Error exn ->
        log_string ~tags
          ("Raised while " ^ msg ^ ":" ^ (Exn.to_string exn));
        Exn.reraise exn msg))
;;

let surround_s ?level ?time ?tags t msg f =
  surround_s_gen
    ?tags
    ~try_with:Monitor.try_with
    ~map_return:Deferred.map
    ~log_sexp:(fun ?tags s -> sexp ?tags ?level ?time t s)
    ~f
    msg
;;

let surroundf ?level ?time ?tags t fmt =
  surroundf_gen
    ?tags
    ~try_with:Monitor.try_with
    ~map_return:Deferred.map
    ~log_string:(fun ?tags -> string ?tags ?level ?time t)
    fmt
;;

let set_level_via_param log =
  let open Command.Param in
  map (flag "log-level" (optional Level.arg) ~doc:"LEVEL The log level") ~f:(function
    | None -> ()
    | Some level -> set_level log level
  )
;;

let raw   ?time ?tags t fmt = printf ?time ?tags t fmt
let debug ?time ?tags t fmt = printf ~level:`Debug ?time ?tags t fmt
let info  ?time ?tags t fmt = printf ~level:`Info  ?time ?tags t fmt
let error ?time ?tags t fmt = printf ~level:`Error ?time ?tags t fmt

let%bench_module "unused log messages" =
  (module struct
    let (log : t) = create ~level:`Info ~output:[Output.file `Text ~filename:"/dev/null"] ~on_error:`Raise

    let%bench "unused printf" = debug log "blah"
    let%bench "unused printf w/subst" = debug log "%s" "blah"
    let%bench "unused string" = string log ~level:`Debug "blah"
    let%bench "used printf" = info log "blah"
  end)

module type Global_intf = sig
  val log : t Lazy.t

  val level        : unit -> Level.t
  val set_level    : Level.t -> unit
  val set_output   : Output.t list -> unit
  val get_output   : unit -> Output.t list
  val set_on_error : [ `Raise | `Call of (Error.t -> unit) ] -> unit
  val would_log    : Level.t option -> bool
  val set_level_via_param : unit -> unit Command.Param.t

  val raw          : ?time:Time.t -> ?tags:(string * string) list -> ('a, unit, string, unit) format4 -> 'a
  val info         : ?time:Time.t -> ?tags:(string * string) list -> ('a, unit, string, unit) format4 -> 'a
  val error        : ?time:Time.t -> ?tags:(string * string) list -> ('a, unit, string, unit) format4 -> 'a
  val debug        : ?time:Time.t -> ?tags:(string * string) list -> ('a, unit, string, unit) format4 -> 'a
  val flushed      : unit -> unit Deferred.t
  val rotate       : unit -> unit Deferred.t

  val printf
    :  ?level:Level.t
    -> ?time:Time.t
    -> ?tags:(string * string) list
    -> ('a, unit, string, unit) format4
    -> 'a

  val sexp
    :  ?level:Level.t
    -> ?time:Time.t
    -> ?tags:(string * string) list
    -> Sexp.t
    -> unit

  val string
    :  ?level:Level.t
    -> ?time:Time.t
    -> ?tags:(string * string) list
    -> string
    -> unit

  val message : Message.t -> unit

  val surround_s
    :  ?level : Level.t
    -> ?time : Time.t
    -> ?tags : (string * string) list
    -> Sexp.t
    -> (unit -> 'a Deferred.t)
    -> 'a Deferred.t

  val surroundf
    :  ?level : Level.t
    -> ?time : Time.t
    -> ?tags : (string * string) list
    -> ('a, unit, string, (unit -> 'b Deferred.t) -> 'b Deferred.t) format4
    -> 'a
end

module Make_global() : Global_intf = struct

  let send_errors_to_top_level_monitor e =
    let e = try Error.raise e with e -> e in
    Monitor.send_exn Monitor.main ~backtrace:`Get e
  ;;

  let log =
    lazy (
      create
        ~level:`Info
        ~output:[Output.stderr ()]
        ~on_error:(`Call send_errors_to_top_level_monitor))
  ;;

  let level ()             = level (Lazy.force log)
  let set_level level      = set_level (Lazy.force log) level
  let set_output output    = set_output (Lazy.force log) output
  let get_output ()        = get_output (Lazy.force log)
  let set_on_error handler = set_on_error (Lazy.force log) handler
  let would_log level      = would_log (Lazy.force log) level

  let raw   ?time ?tags k = raw   ?time ?tags (Lazy.force log) k
  let info  ?time ?tags k = info  ?time ?tags (Lazy.force log) k
  let error ?time ?tags k = error ?time ?tags (Lazy.force log) k
  let debug ?time ?tags k = debug ?time ?tags (Lazy.force log) k

  let flushed () = flushed (Lazy.force log)
  let rotate ()  = rotate (Lazy.force log)

  let printf   ?level ?time ?tags k = printf ?level ?time ?tags (Lazy.force log) k
  let sexp     ?level ?time ?tags s = sexp ?level ?time ?tags (Lazy.force log) s
  let string   ?level ?time ?tags s = string ?level ?time ?tags (Lazy.force log) s
  let message msg                   = message (Lazy.force log) msg

  let surround_s ?level ?time ?tags msg f =
    surround_s ?level ?time ?tags (Lazy.force log) msg f
  ;;

  let surroundf ?level ?time ?tags fmt =
    surroundf ?level ?time ?tags (Lazy.force log) fmt

  let set_level_via_param () =
    set_level_via_param (Lazy.force log)
end

module Blocking : sig
  module Output : sig
    type t

    val create : (Message.t -> unit) -> t
    val stdout : t
    val stderr : t
  end

  val level      : unit -> Level.t
  val set_level  : Level.t -> unit
  val set_output : Output.t -> unit
  val raw        : ?time:Time.t -> ?tags:(string * string) list -> ('a, unit, string, unit) format4 -> 'a
  val info       : ?time:Time.t -> ?tags:(string * string) list -> ('a, unit, string, unit) format4 -> 'a
  val error      : ?time:Time.t -> ?tags:(string * string) list -> ('a, unit, string, unit) format4 -> 'a
  val debug      : ?time:Time.t -> ?tags:(string * string) list -> ('a, unit, string, unit) format4 -> 'a

  val sexp
    :  ?level:Level.t
    -> ?time:Time.t
    -> ?tags:(string * string) list
    -> Sexp.t
    -> unit

  val surround_s
    :  ?level:Level.t
    -> ?time:Time.t
    -> ?tags:(string * string) list
    -> Sexp.t
    -> (unit -> 'a)
    -> 'a

  val surroundf
    :  ?level:Level.t
    -> ?time:Time.t
    -> ?tags:(string * string) list
    -> ('a, unit, string, (unit -> 'b) -> 'b) format4
    -> 'a
end = struct
  module Output = struct
    type t = Message.t -> unit

    let create = ident

    let write print = (fun msg -> print (Message.to_write_only_text msg))
    let stdout      = write (Core.Printf.printf "%s\n%!")
    let stderr      = write (Core.Printf.eprintf "%s\n%!")
  end

  let level : Level.t ref = ref `Info
  let write = ref Output.stderr

  let set_level l = level := l
  let level () = !level

  let set_output output = write := output

  let write msg =
    if Scheduler.is_running ()
    then (failwith "Log.Global.Blocking function called after scheduler started");
    !write msg
  ;;

  let would_log msg_level =
    (* we don't need to test for empty output here because the interface only allows one
       Output.t and ensures that it is always set to something. *)
    Level.as_or_more_verbose_than ~log_level:(level ()) ~msg_level
  ;;

  let gen ?level:msg_level ?time ?tags k =
    ksprintf (fun msg ->
      if would_log msg_level
      then begin
        let msg = `String msg in
        write (Message.create ?level:msg_level ?time ?tags msg)
      end) k;
  ;;

  let string ?level ?time ?tags s =
    if would_log level
    then (write (Message.create ?level ?time ?tags (`String s)))
  ;;

  let raw   ?time ?tags k = gen ?time ?tags k
  let debug ?time ?tags k = gen ~level:`Debug ?time ?tags k
  let info  ?time ?tags k = gen ~level:`Info  ?time ?tags k
  let error ?time ?tags k = gen ~level:`Error ?time ?tags k

  let sexp  ?level ?time ?tags sexp =
    if would_log level
    then (write (Message.create ?level ?time ?tags (`Sexp sexp)))
  ;;

  let surround_s ?level ?time ?tags msg f =
    surround_s_gen
      ?tags
      ~try_with:Result.try_with
      ~map_return:(fun x ~f -> f x)
      ~log_sexp:(sexp ?level ?time)
      ~f
      msg
  ;;

  let surroundf ?level ?time ?tags fmt =
    surroundf_gen
      ?tags
      ~try_with:Result.try_with
      ~map_return:(fun x ~f -> f x)
      ~log_string:(string ?level ?time)
      fmt
  ;;
end

(* Programs that want simplistic single-channel logging can open this module.  It provides
   a global logging facility to a single output type at a single level. *)
module Global = Make_global()

module Reader = struct
  let read_from_reader format r ~pipe_w =
    match format with
    | `Sexp | `Sexp_hum ->
      let sexp_pipe = Reader.read_sexps r in
      Pipe.transfer sexp_pipe pipe_w ~f:Message.t_of_sexp
      >>| fun () ->
      Pipe.close pipe_w
    | `Bin_prot ->
      let rec loop () =
        Reader.read_bin_prot r Message.bin_reader_t
        >>= function
        | `Eof    ->
          Pipe.close pipe_w;
          return ()
        | `Ok msg ->
          Pipe.write pipe_w msg
          >>= loop
      in
      loop ()
  ;;

  let pipe_of_reader format reader =
    Pipe.create_reader ~close_on_exception:false (fun pipe_w ->
      read_from_reader format reader ~pipe_w)
  ;;

  let pipe format filename =
    Pipe.create_reader ~close_on_exception:false (fun pipe_w ->
      Reader.with_file filename ~f:(fun reader ->
        read_from_reader format reader ~pipe_w))
  ;;

  module Expert = struct
    let read_one format reader =
      match format with
      | `Sexp | `Sexp_hum ->
        let%map sexp = Reader.read_sexp reader in
        Reader.Read_result.map sexp ~f:Message.t_of_sexp
      | `Bin_prot ->
        Reader.read_bin_prot reader Message.bin_reader_t
  end
end
