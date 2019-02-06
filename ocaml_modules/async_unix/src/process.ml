open Core
open Import

module Unix = Unix_syscalls

type env = Unix.env [@@deriving sexp]

type t =
  { pid         : Pid.t
  ; stdin       : Writer.t
  ; stdout      : Reader.t
  ; stderr      : Reader.t
  ; prog        : string
  ; args        : string list
  ; working_dir : string option
  ; env         : env
  ; wait        : Unix.Exit_or_signal.t Deferred.t Lazy.t }
[@@deriving fields, sexp_of]

type 'a create
  =  ?buf_len     : int
  -> ?env         : env
  -> ?stdin       : string
  -> ?working_dir : string
  -> prog         : string
  -> args         : string list
  -> unit
  -> 'a Deferred.t

let create
      ?buf_len
      ?(env = `Extend [])
      ?stdin:write_to_stdin
      ?working_dir
      ~prog
      ~args
      ()
  =
  match%map
    In_thread.syscall ~name:"create_process_env" (fun () ->
      Core.Unix.create_process_env ~prog ~args ~env ?working_dir ())
  with
  | Error exn -> Or_error.of_exn exn
  | Ok { pid; stdin; stdout; stderr } ->
    let create_fd name file_descr =
      Fd.create Fifo file_descr
        (Info.create "child process" ~here:[%here] (name, `pid pid, `prog prog, `args args)
           [%sexp_of: string
                      * [ `pid of Pid.t ]
                      * [ `prog of string ]
                      * [ `args of string list ]])
    in
    let stdin =
      let fd = create_fd "stdin" stdin in
      match write_to_stdin with
      | None ->
        Writer.create ?buf_len fd
      | Some _ ->
        Writer.create ?buf_len fd
          ~buffer_age_limit:`Unlimited
          ~raise_when_consumer_leaves:false
    in
    let t =
      { pid
      ; stdin
      ; stdout      = Reader.create ?buf_len (create_fd "stdout" stdout)
      ; stderr      = Reader.create ?buf_len (create_fd "stderr" stderr)
      ; prog
      ; args
      ; working_dir
      ; env
      ; wait        = lazy (Unix.waitpid pid) }
    in
    begin match write_to_stdin with
    | None -> ()
    | Some write_to_stdin -> Writer.write t.stdin write_to_stdin
    end;
    Ok t
;;

let create_exn ?buf_len ?env ?stdin ?working_dir ~prog ~args () =
  create ?buf_len ?env ?stdin ?working_dir ~prog ~args () >>| ok_exn
;;

module Lines_or_sexp = struct
  type t =
    | Lines of string list
    | Sexp of Sexp.t

  let sexp_of_t t =
    match t with
    | Lines ([] | [""]) -> [%sexp ""]
    | Lines lines -> [%sexp (lines : string list)]
    | Sexp sexp -> sexp
  ;;

  let create string =
    try Sexp (Sexp.of_string string)
    with _ -> Lines (String.split ~on:'\n' string)
  ;;
end

module Output = struct
  module Stable = struct
    module V1 = struct
      type t =
        { stdout      : string
        ; stderr      : string
        ; exit_status : Unix.Exit_or_signal.t }
      [@@deriving compare, sexp]
    end
  end

  include Stable.V1

  let sexp_of_t t =
    [%message ""
                ~stdout:(Lines_or_sexp.create t.stdout : Lines_or_sexp.t)
                ~stderr:(Lines_or_sexp.create t.stderr : Lines_or_sexp.t)
                ~exit_status:(t.exit_status : Unix.Exit_or_signal.t)]
  ;;
end

let wait t = force t.wait

let collect_output_and_wait t =
  let stdout = Reader.contents t.stdout in
  let stderr = Reader.contents t.stderr in
  let%bind () = Writer.close t.stdin ~force_close:(Deferred.never ()) in
  let%bind exit_status = wait t in
  let%bind stdout = stdout in
  let%bind stderr = stderr in
  return { Output. stdout; stderr; exit_status }
;;

module Failure = struct

  let should_drop_env = function
    | `Extend [] -> true
    | `Extend (_ :: _) | `Replace _ | `Replace_raw _ -> false
  ;;

  type t =
    { prog        : string
    ; args        : string list
    ; working_dir : string sexp_option
    ; env         : env [@sexp_drop_if should_drop_env]
    ; exit_status : Unix.Exit_or_signal.error
    ; stdout      : Lines_or_sexp.t
    ; stderr      : Lines_or_sexp.t }
  [@@deriving sexp_of]
end

type 'a collect
  =  ?accept_nonzero_exit : int list
  -> t
  -> 'a Deferred.t

let collect_stdout_and_wait ?(accept_nonzero_exit = []) t =
  let%map { stdout; stderr; exit_status } = collect_output_and_wait t in
  match exit_status with
  | Ok () -> Ok stdout
  | Error (`Exit_non_zero n) when List.mem accept_nonzero_exit n ~equal:Int.equal
    -> Ok stdout
  | Error exit_status ->
    let { prog; args; working_dir; env; _ } = t in
    Or_error.error "Process.run failed"
      { Failure.
        prog; args; working_dir; env; exit_status
        ; stdout = Lines_or_sexp.create stdout
        ; stderr = Lines_or_sexp.create stderr }
      [%sexp_of: Failure.t]
;;

let map_collect collect f ?accept_nonzero_exit t =
  let%map a = collect ?accept_nonzero_exit t in
  f a
;;

let collect_stdout_and_wait_exn = map_collect collect_stdout_and_wait ok_exn

let collect_stdout_lines_and_wait =
  map_collect collect_stdout_and_wait (Or_error.map ~f:String.split_lines)
;;

let collect_stdout_lines_and_wait_exn = map_collect collect_stdout_lines_and_wait ok_exn

let%test_unit "first arg is not prog" =
  let args = [ "219068700202774381" ] in
  [%test_pred: string list Or_error.t]
    (Poly.equal (Ok args))
    (Thread_safe.block_on_async_exn
       (fun () ->
          create ~prog:"echo" ~args ()
          >>=? collect_stdout_lines_and_wait))
;;

type 'a run
  =  ?accept_nonzero_exit : int list
  -> ?env                 : env
  -> ?stdin               : string
  -> ?working_dir         : string
  -> prog                 : string
  -> args                 : string list
  -> unit
  -> 'a Deferred.t

let run ?accept_nonzero_exit ?env ?stdin ?working_dir ~prog ~args () =
  match%bind create ?env ?stdin ?working_dir ~prog ~args () with
  | Error _ as e -> return e
  | Ok t -> collect_stdout_and_wait ?accept_nonzero_exit t
;;

let map_run run f ?accept_nonzero_exit ?env ?stdin ?working_dir ~prog ~args () =
  let%map a = run ?accept_nonzero_exit ?env ?stdin ?working_dir ~prog ~args () in
  f a
;;

let run_exn = map_run run ok_exn

let run_lines = map_run run (Or_error.map ~f:String.split_lines)

let run_lines_exn = map_run run_lines ok_exn

let run_expect_no_output ?accept_nonzero_exit ?env ?stdin ?working_dir ~prog ~args () =
  match%map run ?accept_nonzero_exit ?env ?working_dir ?stdin ~prog ~args () with
  | Error _ as err      -> err
  | Ok ""               -> Ok ()
  | Ok non_empty_output ->
    Or_error.error "Process.run_expect_no_output: non-empty output" () (fun () ->
      [%sexp
        { prog   = (prog             : string)
        ; args   = (args             : string list)
        ; output = (non_empty_output : string) }])
;;

let run_expect_no_output_exn = map_run run_expect_no_output ok_exn
