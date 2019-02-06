open Core
open Import

module Fd = Raw_fd
module Watching = Fd.Watching
module Signal = Core.Signal
module Timerfd = Linux_ext.Timerfd

module Tsc = Time_stamp_counter

let debug = Debug.scheduler

module File_descr_watcher = struct
  (* A file descriptor watcher implementation + a watcher.  We need the file-descr watcher
     as a first-class value to support choosing which file-descr watcher to use in
     [go_main].  We could define [t] as [Epoll of ... | Select of ...] and dispatch every
     call, but it is simpler to just pack the file descriptor watcher with its associated
     functions (OO-programming with modules...). *)
  module type S = sig
    include File_descr_watcher_intf.S
    val watcher : t
  end

  type t = (module S)

  let sexp_of_t t =
    let module F = (val t : S) in
    (* Include the backend information so we know which one it is. *)
    [%sexp_of: Config.File_descr_watcher.t * F.t] (F.backend, F.watcher)
  ;;
end

type 'a with_options = 'a Kernel_scheduler.with_options

include struct
  open Kernel_scheduler

  let preserve_execution_context  = preserve_execution_context
  let preserve_execution_context' = preserve_execution_context'
  let schedule                    = schedule
  let schedule'                   = schedule'
  let within                      = within
  let within'                     = within'
  let within_context              = within_context
  let within_v                    = within_v
  let find_local                  = find_local
  let with_local                  = with_local
end

let cycle_count    () = Kernel_scheduler.(cycle_count (t ()))
let cycle_start_ns () = Kernel_scheduler.(cycle_start (t ()))

let cycle_start () = Time_ns.to_time (cycle_start_ns ())

let cycle_times_ns () = Kernel_scheduler.(map_cycle_times (t ())) ~f:Fn.id
let cycle_times    () = Kernel_scheduler.(map_cycle_times (t ())) ~f:Time_ns.Span.to_span

let long_cycles ~at_least = Kernel_scheduler.(long_cycles (t ())) ~at_least

let event_precision_ns () = Kernel_scheduler.(event_precision (t ()))
let event_precision () = Time_ns.Span.to_span (event_precision_ns ())

let set_max_num_jobs_per_priority_per_cycle i =
  Kernel_scheduler.(set_max_num_jobs_per_priority_per_cycle (t ())) i
;;

let max_num_jobs_per_priority_per_cycle () =
  Kernel_scheduler.(max_num_jobs_per_priority_per_cycle (t ()))
;;

let force_current_cycle_to_end () = Kernel_scheduler.(force_current_cycle_to_end (t ()))

type t =
  { (* The scheduler [mutex] must be locked by all code that is manipulating scheduler
       data structures, which is almost all async code.  The [mutex] is automatically
       locked in the main thread when the scheduler is first created.  A [Nano_mutex]
       keeps track of which thread is holding the lock.  This means we can detect errors
       in which code incorrectly accesses async from a thread not holding the lock.  We do
       this when [detect_invalid_access_from_thread = true].  We also detect errors in
       which code tries to acquire the async lock while it already holds it, or releases
       the lock when it doesn't hold it. *)
    mutex                                  : Nano_mutex.t

  ; mutable is_running                     : bool
  ; mutable have_called_go                 : bool

  (* [fds_whose_watching_has_changed] holds all fds whose watching has changed since
     the last time their desired state was set in the [file_descr_watcher]. *)
  ; mutable fds_whose_watching_has_changed : Fd.t list
  ; file_descr_watcher                     : File_descr_watcher.t
  ; mutable time_spent_waiting_for_io      : Tsc.Span.t

  (* [fd_by_descr] holds every file descriptor that Async knows about.  Fds are added
     when they are created, and removed when they transition to [Closed]. *)
  ; fd_by_descr                            : Fd_by_descr.t

  (* If we are using a file descriptor watcher that does not support sub-millisecond
     timeout, [timerfd] contains a timerfd used to handle the next expiration.
     [timerfd_set_at] holds the the time at which [timerfd] is set to expire.  This
     lets us avoid calling [Time_ns.now] and [Linux_ext.Timerfd.set_after] unless
     we need to change that time. *)
  ; mutable timerfd                        : Linux_ext.Timerfd.t option
  ; mutable timerfd_set_at                 : Time_ns.t

  (* A distinguished thread, called the "scheduler" thread, is continually looping,
     checking file descriptors for I/O and then running a cycle.  It manages
     the [file_descr_watcher] and runs signal handlers.

     [scheduler_thread_id] is mutable because we create the scheduler before starting
     the scheduler running.  Once we start running the scheduler, [scheduler_thread_id]
     is set and never changes again. *)
  ; mutable scheduler_thread_id            : int

  (* The [interruptor] is used to wake up the scheduler when it is blocked on the file
     descriptor watcher. *)
  ; interruptor                            : Interruptor.t

  ; signal_manager                         : Raw_signal_manager.t

  (* The [thread_pool] is used for making blocking system calls in threads other than
     the scheduler thread, and for servicing [In_thread.run] requests. *)
  ; thread_pool                            : Thread_pool.t

  (* [handle_thread_pool_stuck] is called once per second if the thread pool is"stuck",
     i.e has not completed a job for one second and has no available threads. *)
  ; mutable handle_thread_pool_stuck       : stuck_for:Time_ns.Span.t -> unit

  ; busy_pollers                           : Busy_pollers.t
  ; mutable busy_poll_thread_is_running    : bool

  ; mutable next_tsc_calibration           : Time_stamp_counter.t

  ; kernel_scheduler                       : Kernel_scheduler.t

  (* [have_lock_do_cycle] is used to customize the implementation of running a cycle.
     E.g. in Ecaml it is set to something that causes Emacs to run a cycle. *)
  ; mutable have_lock_do_cycle             : (unit -> unit) option

  (* configuration*)
  ; mutable max_inter_cycle_timeout        : Max_inter_cycle_timeout.t
  ; mutable min_inter_cycle_timeout        : Min_inter_cycle_timeout.t
  ; mutable may_sleep_for_thread_fairness  : bool }
[@@deriving fields, sexp_of]

let max_num_threads t = Thread_pool.max_num_threads t.thread_pool

let max_num_open_file_descrs t = Fd_by_descr.capacity t.fd_by_descr

let current_execution_context t =
  Kernel_scheduler.current_execution_context t.kernel_scheduler;
;;

let with_execution_context t context ~f =
  Kernel_scheduler.with_execution_context t.kernel_scheduler context ~f;
;;

let create_fd ?avoid_nonblock_if_possible t kind file_descr info =
  let fd = Fd.create ?avoid_nonblock_if_possible kind file_descr info in
  match Fd_by_descr.add t.fd_by_descr fd with
  | Ok () -> fd
  | Error error ->
    let backtrace =
      if am_running_inline_test
      then None
      else (Some (Backtrace.get ()))
    in
    raise_s [%message
      "\
Async was unable to add a file descriptor to its table of open file descriptors"
        (file_descr : File_descr.t)
        (error : Error.t)
        (backtrace : Backtrace.t sexp_option)
        ~scheduler:(if am_running_inline_test then None else (Some t) : t sexp_option)]
;;

let lock t =
  (* The following debug message is outside the lock, and so there can be races between
     multiple threads printing this message. *)
  if debug then (Debug.log_string "waiting on lock");
  Nano_mutex.lock_exn t.mutex;
;;

let try_lock t =
  match Nano_mutex.try_lock_exn t.mutex with
  | `Acquired -> true
  | `Not_acquired -> false
;;

let unlock t =
  if debug then (Debug.log_string "lock released");
  Nano_mutex.unlock_exn t.mutex;
;;

let with_lock t f =
  lock t;
  protect ~f ~finally:(fun () -> unlock t);
;;

let am_holding_lock t = Nano_mutex.current_thread_has_lock t.mutex

type the_one_and_only =
  | Not_ready_to_initialize
  | Ready_to_initialize of (unit -> t)
  | Initialized of t

(* We use a mutex to protect creation of the one-and-only scheduler in the event that
   multiple threads attempt to call [the_one_and_only] simultaneously, which can
   happen in programs that are using [Thread_safe.run_in_async]. *)
let mutex_for_initializing_the_one_and_only_ref = Nano_mutex.create ()
let the_one_and_only_ref : the_one_and_only ref = ref Not_ready_to_initialize

let is_ready_to_initialize () =
  match !the_one_and_only_ref with
  | Not_ready_to_initialize | Initialized _ -> false
  | Ready_to_initialize _ -> true
;;

(* Handling the uncommon cases in this function allows [the_one_and_only] to be inlined.
   The presence of a string constant keeps this function from being inlined. *)
let the_one_and_only_uncommon_case ~should_lock =
  Nano_mutex.critical_section mutex_for_initializing_the_one_and_only_ref ~f:(fun () ->
    match !the_one_and_only_ref with
    | Initialized t -> t
    | Not_ready_to_initialize ->
      raise_s [%message "Async the_one_and_only not ready to initialize"]
    | Ready_to_initialize f ->
      let t = f () in
      (* We supply [~should_lock:true] to lock the scheduler when the user does async
         stuff at the top level before calling [Scheduler.go], because we don't want
         anyone to be able to run jobs until [Scheduler.go] is called.  This could happen,
         e.g. by creating a reader that does a read system call in another (true) thread.
         The scheduler will remain locked until the scheduler unlocks it. *)
      if should_lock then (lock t);
      the_one_and_only_ref := Initialized t;
      t)
;;

let the_one_and_only ~should_lock =
  match !the_one_and_only_ref with
  | Initialized t -> t
  | Not_ready_to_initialize | Ready_to_initialize _ ->
    the_one_and_only_uncommon_case ~should_lock
;;

let current_thread_id () = Core.Thread.(id (self ()))

let is_main_thread () = current_thread_id () = 0

let remove_fd t fd = Fd_by_descr.remove t.fd_by_descr fd

let maybe_start_closing_fd t (fd : Fd.t) =
  if fd.num_active_syscalls = 0
  then (
    match fd.state with
    | Closed | Open _ -> ()
    | Close_requested (execution_context, do_close_syscall) ->
      (* We must remove the fd now and not after the close has finished.  If we waited
         until after the close had finished, then the fd might have already been
         reused by the OS and replaced. *)
      remove_fd t fd;
      Fd.set_state fd Closed;
      Kernel_scheduler.enqueue t.kernel_scheduler execution_context do_close_syscall ());
;;

let dec_num_active_syscalls_fd t (fd : Fd.t) =
  fd.num_active_syscalls <- fd.num_active_syscalls - 1;
  maybe_start_closing_fd t fd;
;;

let invariant t : unit =
  try
    let check invariant field = invariant (Field.get field t) in
    Fields.iter
      ~mutex:ignore
      ~have_lock_do_cycle:ignore
      ~is_running:ignore
      ~have_called_go:ignore
      ~fds_whose_watching_has_changed:(check (fun fds_whose_watching_has_changed ->
        List.iter fds_whose_watching_has_changed ~f:(fun (fd : Fd.t) ->
          assert fd.watching_has_changed;
          begin match Fd_by_descr.find t.fd_by_descr fd.file_descr with
          | None -> assert false
          | Some fd' -> assert (phys_equal fd fd')
          end)))
      ~file_descr_watcher:(check (fun file_descr_watcher ->
        let module F = (val file_descr_watcher : File_descr_watcher.S) in
        F.invariant F.watcher;
        F.iter F.watcher ~f:(fun file_descr _ ->
          try
            match Fd_by_descr.find t.fd_by_descr file_descr with
            | None -> raise_s [%message "missing from fd_by_descr"]
            | Some fd -> assert (Fd.num_active_syscalls fd > 0);
          with exn ->
            raise_s [%message "fd problem" (exn : exn) (file_descr : File_descr.t)])))
      ~time_spent_waiting_for_io:ignore
      ~fd_by_descr:(check (fun fd_by_descr ->
        Fd_by_descr.invariant fd_by_descr;
        Fd_by_descr.iter fd_by_descr ~f:(fun fd ->
          if fd.watching_has_changed
          then
            (assert (List.exists t.fds_whose_watching_has_changed ~f:(fun fd' ->
               phys_equal fd fd'))))))
      ~timerfd:ignore
      ~timerfd_set_at:ignore
      ~scheduler_thread_id:ignore
      ~interruptor:(check Interruptor.invariant)
      ~signal_manager:(check Raw_signal_manager.invariant)
      ~thread_pool:(check Thread_pool.invariant)
      ~handle_thread_pool_stuck:ignore
      ~busy_pollers:(check Busy_pollers.invariant)
      ~busy_poll_thread_is_running:ignore
      ~next_tsc_calibration:ignore
      ~kernel_scheduler:(check Kernel_scheduler.invariant)
      ~max_inter_cycle_timeout:ignore
      ~min_inter_cycle_timeout:(check (fun min_inter_cycle_timeout ->
        assert (Time_ns.Span.( <= )
                  (Min_inter_cycle_timeout.raw min_inter_cycle_timeout)
                  (Max_inter_cycle_timeout.raw t.max_inter_cycle_timeout))))
      ~may_sleep_for_thread_fairness:ignore
  with exn ->
    raise_s [%message "Scheduler.invariant failed" (exn : exn) ~scheduler:(t : t)]
;;

let update_check_access t do_check =
  Kernel_scheduler.set_check_access t.kernel_scheduler
    (if not do_check
     then None
     else (
       Some (fun () ->
         if not (am_holding_lock t)
         then (
           Debug.log "attempt to access Async from thread not holding the Async lock"
             (Backtrace.get (), t, Time.now ())
             [%sexp_of: Backtrace.t * t * Time.t];
           exit 1))))
;;

(* Try to create a timerfd.  It returns [None] if [Core] is not built with timerfd support
   or if it is not available on the current system. *)
let try_create_timerfd () =
  match Timerfd.create with
  | Error _ -> None
  | Ok create ->
    let clock = Timerfd.Clock.realtime in
    try
      Some (create clock ~flags:Timerfd.Flags.(nonblock + cloexec))
    with
    | Unix.Unix_error (ENOSYS, _, _) ->
      (* Kernel too old. *)
      None
    | Unix.Unix_error (EINVAL, _, _) ->
      (* Flags are only supported with Linux >= 2.6.27, try without them. *)
      let timerfd = create clock in
      Unix.set_close_on_exec (timerfd : Timerfd.t :> Unix.File_descr.t);
      Unix.set_nonblock      (timerfd : Timerfd.t :> Unix.File_descr.t);
      Some timerfd
;;

let default_handle_thread_pool_stuck ~stuck_for =
  if Time_ns.Span.(>=) stuck_for Config.report_thread_pool_stuck_for
  then (
    let now = Time_ns.now () in
    let message =
      sprintf "\
%s: All %d threads in Async's thread pool have been blocked for at least %s.
  Please check code in your program that uses threads, e.g. [In_thread.run]."
        (Time.format (Time_ns.to_time now) "%F %T %Z" ~zone:(force Time.Zone.local))
        (Validated.raw Config.max_num_threads)
        (Time_ns.Span.to_short_string stuck_for)
    in
    if Time_ns.Span.(>=) stuck_for Config.abort_after_thread_pool_stuck_for
    then (Monitor.send_exn Monitor.main (Failure message))
    else (
      Core.eprintf "\
%s
  This is only a warning.  It will raise an exception in %s.
%!"
        message
        (Time_ns.Span.to_short_string
           (Time_ns.Span.(-) Config.abort_after_thread_pool_stuck_for stuck_for))));
;;

let detect_stuck_thread_pool t =
  let is_stuck = ref false in
  let became_stuck_at = ref Time_ns.epoch in
  let stuck_num_work_completed = ref 0 in
  Clock.every (sec 1.) ~continue_on_error:false (fun () ->
    if not (Thread_pool.has_unstarted_work t.thread_pool)
    then (is_stuck := false)
    else (
      let now = Time_ns.now () in
      let num_work_completed = Thread_pool.num_work_completed t.thread_pool in
      if !is_stuck && num_work_completed = !stuck_num_work_completed
      then (t.handle_thread_pool_stuck ~stuck_for:(Time_ns.diff now !became_stuck_at))
      else (
        is_stuck := true;
        became_stuck_at := now;
        stuck_num_work_completed := num_work_completed)));
;;

let thread_safe_wakeup_scheduler t = Interruptor.thread_safe_interrupt t.interruptor

let i_am_the_scheduler t = current_thread_id () = t.scheduler_thread_id

let set_fd_desired_watching t (fd : Fd.t) read_or_write desired =
  Read_write.set fd.watching read_or_write desired;
  if not fd.watching_has_changed
  then (
    fd.watching_has_changed <- true;
    t.fds_whose_watching_has_changed <- fd :: t.fds_whose_watching_has_changed)
;;

let request_start_watching t fd read_or_write watching =
  if Debug.file_descr_watcher
  then (Debug.log "request_start_watching" (read_or_write, fd, t)
          [%sexp_of: Read_write.Key.t * Fd.t * t]);
  if not fd.supports_nonblock
  (* Some versions of epoll complain if one asks it to monitor a file descriptor that
     doesn't support nonblocking I/O, e.g. a file.  So, we never ask the
     file-descr-watcher to monitor such descriptors. *)
  then `Unsupported
  else (
    let result =
      match Read_write.get fd.watching read_or_write with
      | Watch_once _ | Watch_repeatedly _ -> `Already_watching
      | Stop_requested ->
        (* We don't [inc_num_active_syscalls] in this case, because we already did when we
           transitioned from [Not_watching] to [Watching].  Also, it is possible that [fd]
           was closed since we transitioned to [Stop_requested], in which case we don't want
           to [start_watching]; we want to report that it was closed and leave it
           [Stop_requested] so the the file-descr-watcher will stop watching it and we can
           actually close it. *)
        if Fd.is_closed fd
        then `Already_closed
        else `Watching
      | Not_watching ->
        match Fd.inc_num_active_syscalls fd with
        | `Already_closed -> `Already_closed
        | `Ok -> `Watching
    in
    begin match result with
    | `Already_closed | `Already_watching -> ()
    | `Watching ->
      set_fd_desired_watching t fd read_or_write watching;
      if not (i_am_the_scheduler t) then (thread_safe_wakeup_scheduler t);
    end;
    result);
;;

let request_stop_watching t fd read_or_write value =
  if Debug.file_descr_watcher
  then (
    Debug.log "request_stop_watching" (read_or_write, value, fd, t)
      [%sexp_of: Read_write.Key.t * Fd.ready_to_result * Fd.t * t]);
  match Read_write.get fd.watching read_or_write with
  | Stop_requested | Not_watching -> ()
  | Watch_once ready_to ->
    Ivar.fill ready_to value;
    set_fd_desired_watching t fd read_or_write Stop_requested;
    if not (i_am_the_scheduler t) then (thread_safe_wakeup_scheduler t);
  | Watch_repeatedly (job, finished) ->
    match value with
    | `Ready -> Kernel_scheduler.enqueue_job t.kernel_scheduler job ~free_job:false
    | `Closed | `Bad_fd | `Interrupted as value ->
      Ivar.fill finished value;
      set_fd_desired_watching t fd read_or_write Stop_requested;
      if not (i_am_the_scheduler t) then (thread_safe_wakeup_scheduler t);
;;

let post_check_handle_fd t file_descr read_or_write value =
  if Fd_by_descr.mem t.fd_by_descr file_descr
  then (
    let fd = Fd_by_descr.find_exn t.fd_by_descr file_descr in
    request_stop_watching t fd read_or_write value)
  else (
    match t.timerfd with
    | Some tfd when File_descr.equal file_descr (tfd :> Unix.File_descr.t) ->
      begin match read_or_write with
      | `Read ->
        (* We don't need to actually call [read] since we are using the
           edge-triggered behavior. *)
        ()
      | `Write ->
        raise_s [%message
          "File_descr_watcher returned the timerfd as ready to be written to"
            (file_descr : File_descr.t)]
      end
    | _ ->
      raise_s [%message
        "File_descr_watcher returned unknown file descr" (file_descr : File_descr.t)])
;;

let create
      ?(file_descr_watcher       = Config.file_descr_watcher)
      ?(max_num_open_file_descrs = Config.max_num_open_file_descrs)
      ?(max_num_threads          = Config.max_num_threads)
      () =
  if debug then (Debug.log_string "creating scheduler");
  let thread_pool =
    ok_exn (Thread_pool.create ~max_num_threads:(Max_num_threads.raw max_num_threads))
  in
  let num_file_descrs = Max_num_open_file_descrs.raw max_num_open_file_descrs in
  let fd_by_descr = Fd_by_descr.create ~num_file_descrs in
  let create_fd kind file_descr info =
    let fd = Fd.create kind file_descr info in
    ok_exn (Fd_by_descr.add fd_by_descr fd);
    fd
  in
  let interruptor = Interruptor.create ~create_fd in
  let t_ref = ref None in (* set below, after [t] is defined *)
  let handle_fd read_or_write ready_or_bad_fd =
    fun file_descr ->
      match !t_ref with
      | None -> assert false
      | Some t -> post_check_handle_fd t file_descr read_or_write ready_or_bad_fd
  in
  let handle_fd_read_ready  = handle_fd `Read  `Ready  in
  let handle_fd_read_bad    = handle_fd `Read  `Bad_fd in
  let handle_fd_write_ready = handle_fd `Write `Ready  in
  let handle_fd_write_bad   = handle_fd `Write `Bad_fd in
  let file_descr_watcher, timerfd =
    match file_descr_watcher with
    | Select ->
      let watcher =
        Select_file_descr_watcher.create ~num_file_descrs
          ~handle_fd_read_ready
          ~handle_fd_read_bad
          ~handle_fd_write_ready
          ~handle_fd_write_bad
      in
      let module W = struct
        include Select_file_descr_watcher
        let watcher = watcher
      end in
      ((module W : File_descr_watcher.S), None)
    | Epoll | Epoll_if_timerfd ->
      let timerfd =
        match try_create_timerfd () with
        | None ->
          raise_s [%message "\
Async refuses to run using epoll on a system that doesn't support timer FDs, since
Async will be unable to timeout with sub-millisecond precision."]
        | Some timerfd -> timerfd
      in
      let watcher =
        Epoll_file_descr_watcher.create ~num_file_descrs ~timerfd
          ~handle_fd_read_ready
          ~handle_fd_write_ready
      in
      let module W = struct
        include Epoll_file_descr_watcher
        let watcher = watcher
      end in
      ((module W : File_descr_watcher.S), Some timerfd)
  in
  let kernel_scheduler = Kernel_scheduler.t () in
  let t =
    { mutex                          = Nano_mutex.create ()
    ; is_running                     = false
    ; have_called_go                 = false
    ; fds_whose_watching_has_changed = []
    ; file_descr_watcher
    ; time_spent_waiting_for_io      = Tsc.Span.of_int_exn 0
    ; fd_by_descr
    ; timerfd
    ; timerfd_set_at                 = Time_ns.max_value
    ; scheduler_thread_id            = -1 (* set when [be_the_scheduler] is called *)
    ; interruptor
    ; signal_manager                 =
        Raw_signal_manager.create ~thread_safe_notify_signal_delivered:(fun () ->
          Interruptor.thread_safe_interrupt interruptor)
    ; thread_pool
    ; handle_thread_pool_stuck       = default_handle_thread_pool_stuck
    ; busy_pollers                   = Busy_pollers.create ()
    ; busy_poll_thread_is_running    = false
    ; next_tsc_calibration           = Time_stamp_counter.now ()
    ; kernel_scheduler
    ; have_lock_do_cycle             = None
    ; max_inter_cycle_timeout        = Config.max_inter_cycle_timeout
    ; min_inter_cycle_timeout        = Config.min_inter_cycle_timeout
    ; may_sleep_for_thread_fairness = false }
  in
  t_ref := Some t;
  detect_stuck_thread_pool t;
  update_check_access t Config.detect_invalid_access_from_thread;
  t
;;

let init () = the_one_and_only_ref := Ready_to_initialize (fun () -> create ())

let () = init ()

let reset_in_forked_process () =
  begin match !the_one_and_only_ref with
  | Not_ready_to_initialize | Ready_to_initialize _ -> ()
  | Initialized { file_descr_watcher; timerfd; _ } ->
    let module F = (val file_descr_watcher : File_descr_watcher.S) in
    F.reset_in_forked_process F.watcher;
    match timerfd with
    | None -> ()
    | Some tfd -> Unix.close (tfd :> Unix.File_descr.t)
  end;
  Kernel_scheduler.reset_in_forked_process ();
  init ();
;;

(* [thread_safe_reset] shuts down Async, exiting the scheduler thread, freeing up all
   Async resources (file descriptors, threads), and resetting Async global state, so that
   one can recreate a new Async scheduler afterwards.  [thread_safe_reset] blocks until
   the shutdown is complete; it must be called from outside Async, e.g. the main
   thread. *)
let thread_safe_reset () =
  match !the_one_and_only_ref with
  | Not_ready_to_initialize | Ready_to_initialize _ -> ()
  | Initialized t ->
    assert (not (am_holding_lock t));
    Thread_pool.finished_with t.thread_pool;
    Thread_pool.block_until_finished t.thread_pool;
    (* We now schedule a job that, when it runs, exits the scheduler thread.  We then wait
       for that job to run.  We acquire the Async lock so that we can schedule the job,
       but release it before we block, so that the scheduler can acquire it. *)
    let scheduler_thread_finished = Thread_safe_ivar.create () in
    with_lock t (fun () ->
      schedule (fun () ->
        Thread_safe_ivar.fill scheduler_thread_finished ();
        Thread.exit ()));
    Thread_safe_ivar.read scheduler_thread_finished;
    reset_in_forked_process ();
;;

let make_async_unusable () =
  reset_in_forked_process ();
  Kernel_scheduler.make_async_unusable ();
  the_one_and_only_ref :=
    Ready_to_initialize (fun () ->
      raise_s [%sexp "Async is unusable due to [Scheduler.make_async_unusable]"])
;;

let thread_safe_enqueue_external_job t f =
  Kernel_scheduler.thread_safe_enqueue_external_job t.kernel_scheduler f
;;

let have_lock_do_cycle t =
  if debug then (Debug.log "have_lock_do_cycle" t [%sexp_of: t]);
  match t.have_lock_do_cycle with
  | Some f -> f ()
  | None ->
    Kernel_scheduler.run_cycle t.kernel_scheduler;
    (* If we are not the scheduler, wake it up so it can process any remaining jobs, clock
       events, or an unhandled exception. *)
    if not (i_am_the_scheduler t) then (thread_safe_wakeup_scheduler t);
;;

let sync_changed_fds_to_file_descr_watcher t =
  match t.fds_whose_watching_has_changed with
  | [] -> ()
  | changed ->
    let module F = (val t.file_descr_watcher : File_descr_watcher.S) in
    let[@inline always] make_file_descr_watcher_agree_with (fd : Fd.t)  =
      fd.watching_has_changed <- false;
      let desired =
        Read_write.mapi fd.watching ~f:(fun read_or_write watching ->
          match watching with
          | Watch_once _ | Watch_repeatedly _ -> true
          | Not_watching -> false
          | Stop_requested ->
            Read_write.set fd.watching read_or_write Not_watching;
            dec_num_active_syscalls_fd t fd;
            false)
      in
      if Debug.file_descr_watcher
      then (
        Debug.log "File_descr_watcher.set" (fd.file_descr, desired, F.watcher)
          [%sexp_of: File_descr.t * bool Read_write.t * F.t]);
      try
        F.set F.watcher fd.file_descr desired
      with exn ->
        raise_s [%message
          "sync_changed_fds_to_file_descr_watcher unable to set fd"
            (desired : bool Read_write.t) (fd : Fd.t) (exn : exn) ~scheduler:(t : t)]
    in
    t.fds_whose_watching_has_changed <- [];
    List.iter changed ~f:make_file_descr_watcher_agree_with;
;;

let maybe_calibrate_tsc t =
  let now = Tsc.now () in
  if Tsc.compare now t.next_tsc_calibration >= 0 then (
    Tsc.Calibrator.calibrate ();
    t.next_tsc_calibration <- Tsc.add now (Tsc.Span.of_ns (Int63.of_int 1_000_000_000)); );
;;

let create_job ?execution_context t f x =
  let execution_context =
    match execution_context with
    | Some e -> e
    | None -> current_execution_context t
  in
  Kernel_scheduler.create_job t.kernel_scheduler execution_context f x
;;

let dump_core_on_job_delay () =
  match Config.dump_core_on_job_delay with
  | Do_not_watch -> ()
  | Watch { dump_if_delayed_by; how_to_dump } ->
    Dump_core_on_job_delay.start_watching
      ~dump_if_delayed_by:(Time_ns.Span.to_span dump_if_delayed_by)
      ~how_to_dump
;;

let be_the_scheduler ?(raise_unhandled_exn = false) t =
  dump_core_on_job_delay ();
  let module F = (val t.file_descr_watcher : File_descr_watcher.S) in
  Kernel_scheduler.set_thread_safe_external_job_hook t.kernel_scheduler
    (fun () -> thread_safe_wakeup_scheduler t);
  t.scheduler_thread_id <- current_thread_id ();
  (* We handle [Signal.pipe] so that write() calls on a closed pipe/socket get EPIPE but
     the process doesn't die due to an unhandled SIGPIPE. *)
  Raw_signal_manager.manage t.signal_manager Signal.pipe;
  (* We avoid allocation in [check_file_descr_watcher], since it is called every time in
     the scheduler loop. *)
  let check_file_descr_watcher ~timeout span_or_unit =
    if Debug.file_descr_watcher
    then (Debug.log "File_descr_watcher.pre_check" t [%sexp_of: t]);
    let pre = F.pre_check F.watcher in
    unlock t;
    (* If the thread pool has threads with work to do, then we yield via nanosleep, which
       releases the OCaml lock and gives them a chance to run.  This is an
       over-approximation of the condition that we actually want to check, which is
       whether there are any threads waiting to acquire the OCaml lock. *)
    if t.may_sleep_for_thread_fairness
    && Thread_pool.unfinished_work t.thread_pool > 0
    then (ignore (Unix.nanosleep 1E-9 : float));
    if Debug.file_descr_watcher
    then (
      Debug.log "File_descr_watcher.thread_safe_check"
        (File_descr_watcher_intf.Timeout.variant_of timeout span_or_unit, t)
        [%sexp_of: [ `Never | `Immediately | `After of Time_ns.Span.t ] * t]);
    let before = Tsc.now () in
    let check_result = F.thread_safe_check F.watcher pre timeout span_or_unit in
    let after = Tsc.now () in
    t.time_spent_waiting_for_io <-
      Tsc.Span.( + ) t.time_spent_waiting_for_io (Tsc.diff after before);
    lock t;
    check_result
  in
  (* We compute the timeout as the last thing before [check_file_descr_watcher], because
     we want to make sure the timeout is zero if there are any scheduled jobs.  The code
     is structured to avoid calling [Time_ns.now] and [Linux_ext.Timerfd.set_*] if
     possible.  In particular, we only call [Time_ns.now] if we need to compute the
     timeout-after span.  And we only call [Linux_ext.Timerfd.set_after] if the time that
     we want it to fire is different than the time it is already set to fire. *)
  let compute_timeout_and_check_file_descr_watcher () =
    let min_inter_cycle_timeout = (t.min_inter_cycle_timeout :> Time_ns.Span.t) in
    let max_inter_cycle_timeout = (t.max_inter_cycle_timeout :> Time_ns.Span.t) in
    let file_descr_watcher_timeout =
      match t.timerfd with
      | None ->
        (* Since there is no timerfd, use the file descriptor watcher timeout. *)
        if Kernel_scheduler.can_run_a_job t.kernel_scheduler
        then min_inter_cycle_timeout
        else if not (Kernel_scheduler.has_upcoming_event t.kernel_scheduler)
        then max_inter_cycle_timeout
        else (
          let next_event_at =
            Kernel_scheduler.next_upcoming_event_exn t.kernel_scheduler
          in
          Time_ns.Span.min
            max_inter_cycle_timeout
            (Time_ns.Span.max
               min_inter_cycle_timeout
               (Time_ns.diff next_event_at (Time_ns.now ()))))
      | Some timerfd ->
        (* Set [timerfd] to fire if necessary, taking into account [can_run_a_job],
           [min_inter_cycle_timeout], and [next_event_at]. *)
        let have_min_inter_cycle_timeout =
          Time_ns.Span.( > ) min_inter_cycle_timeout Time_ns.Span.zero
        in
        if Kernel_scheduler.can_run_a_job t.kernel_scheduler
        then (
          if not have_min_inter_cycle_timeout
          then Time_ns.Span.zero
          else (
            t.timerfd_set_at <- Time_ns.max_value;
            Linux_ext.Timerfd.set_after timerfd min_inter_cycle_timeout;
            max_inter_cycle_timeout))
        else if not (Kernel_scheduler.has_upcoming_event t.kernel_scheduler)
        then max_inter_cycle_timeout
        else (
          let next_event_at =
            Kernel_scheduler.next_upcoming_event_exn t.kernel_scheduler
          in
          let set_timerfd_at =
            if not have_min_inter_cycle_timeout
            then next_event_at
            else (
              Time_ns.max
                next_event_at
                (Time_ns.add (Time_ns.now ()) min_inter_cycle_timeout))
          in
          if not (Time_ns.equal t.timerfd_set_at set_timerfd_at)
          then (
            t.timerfd_set_at <- set_timerfd_at;
            Linux_ext.Timerfd.set_at timerfd set_timerfd_at);
          max_inter_cycle_timeout)
    in
    if Time_ns.Span.( <= ) file_descr_watcher_timeout Time_ns.Span.zero
    then (check_file_descr_watcher ~timeout:Immediately ())
    else (check_file_descr_watcher ~timeout:After file_descr_watcher_timeout)
  in
  begin
    let interruptor_finished = Ivar.create () in
    let interruptor_read_fd = Interruptor.read_fd t.interruptor in
    let problem_with_interruptor () =
      raise_s [%message
        "can not watch interruptor" (interruptor_read_fd : Fd.t) ~scheduler:(t : t)]
    in
    begin match
      request_start_watching t interruptor_read_fd `Read
        (Watch_repeatedly
           (Kernel_scheduler.create_job t.kernel_scheduler
              Execution_context.main Fn.ignore (),
            interruptor_finished))
    with
    | `Already_watching | `Watching -> ()
    | `Unsupported | `Already_closed -> problem_with_interruptor ()
    end;
    upon (Ivar.read interruptor_finished) (fun _ -> problem_with_interruptor ());
  end;
  let rec loop () =
    (* At this point, we have the lock. *)
    if Kernel_scheduler.check_invariants t.kernel_scheduler then (invariant t);
    maybe_calibrate_tsc t;
    match Kernel_scheduler.uncaught_exn t.kernel_scheduler with
    | Some error -> unlock t; error
    | None ->
      sync_changed_fds_to_file_descr_watcher t;
      let check_result = compute_timeout_and_check_file_descr_watcher () in
      (* We call [Interruptor.clear] after [thread_safe_check] and before any of the
         processing that needs to happen in response to [thread_safe_interrupt].  That
         way, even if [Interruptor.clear] clears out an interrupt that hasn't been
         serviced yet, the interrupt will still be serviced by the immediately following
         processing. *)
      Interruptor.clear t.interruptor;
      if Debug.file_descr_watcher
      then (
        Debug.log "File_descr_watcher.post_check" (check_result, t)
          [%sexp_of: F.Check_result.t * t]);
      F.post_check F.watcher check_result;
      if debug then (Debug.log_string "handling delivered signals");
      Raw_signal_manager.handle_delivered t.signal_manager;
      have_lock_do_cycle t;
      loop ();
  in
  let exn =
    try `User_uncaught (loop ())
    with exn -> `Async_uncaught exn
  in
  let should_dump_core, error =
    match exn with
    | `User_uncaught error -> false, error
    | `Async_uncaught exn ->
      true, Error.create "bug in async scheduler" (exn, t) [%sexp_of: exn * t]
  in
  if raise_unhandled_exn
  then (Error.raise error)
  else (
    (* One reason to run [do_at_exit] handlers before printing out the error message is
       that it helps curses applications bring the terminal in a good state, otherwise the
       error message might get corrupted.  Also, the OCaml top-level uncaught exception
       handler does the same. *)
    (try Pervasives.do_at_exit () with _ -> ());
    Debug.log "unhandled exception in Async scheduler" error [%sexp_of: Error.t];
    if should_dump_core
    then (
      Debug.log_string "dumping core";
      Dump_core_on_job_delay.dump_core ());
    Unix.exit_immediately 1);
;;

let add_finalizer t heap_block f =
  Kernel_scheduler.add_finalizer t.kernel_scheduler heap_block f
;;

let add_finalizer_exn t x f =
  add_finalizer t (Heap_block.create_exn x)
    (fun heap_block -> f (Heap_block.value heap_block))
;;

let go ?raise_unhandled_exn () =
  if debug then (Debug.log_string "Scheduler.go");
  let t = the_one_and_only ~should_lock:false in
  (* [go] is called from the main thread and so must acquire the lock if the thread has
     not already done so implicitly via use of an async operation that uses
     [the_one_and_only]. *)
  if not (am_holding_lock t) then (lock t);
  if t.have_called_go then (raise_s [%message "cannot Scheduler.go more than once"]);
  t.have_called_go <- true;
  if not t.is_running
  then (
    t.is_running <- true;
    be_the_scheduler t ?raise_unhandled_exn)
  else (
    unlock t;
    (* We wakeup the scheduler so it can respond to whatever async changes this thread
       made. *)
    thread_safe_wakeup_scheduler t;
    (* Since the scheduler is already running, so we just pause forever. *)
    Time.pause_forever ());
;;

let go_main
      ?raise_unhandled_exn
      ?file_descr_watcher
      ?max_num_open_file_descrs
      ?max_num_threads
      ~main () =
  if not (is_ready_to_initialize ())
  then (raise_s [%message "Async was initialized prior to [Scheduler.go_main]"]);
  let max_num_open_file_descrs =
    Option.map max_num_open_file_descrs ~f:Max_num_open_file_descrs.create_exn
  in
  let max_num_threads =
    Option.map max_num_threads ~f:Max_num_threads.create_exn
  in
  the_one_and_only_ref :=
    Ready_to_initialize (fun () ->
      create
        ?file_descr_watcher
        ?max_num_open_file_descrs
        ?max_num_threads
        ());
  Deferred.upon (return ()) main;
  go ?raise_unhandled_exn ();
;;

let is_running () =
  if (is_ready_to_initialize ())
  then false
  else (the_one_and_only ~should_lock:false).is_running
;;

let report_long_cycle_times ?(cutoff = sec 1.) () =
  Stream.iter (long_cycles ~at_least:(cutoff |> Time_ns.Span.of_span))
    ~f:(fun span ->
      eprintf "%s\n%!"
        (Error.to_string_hum
           (Error.create "long async cycle" span [%sexp_of: Time_ns.Span.t])))
;;

let set_check_invariants bool =
  Kernel_scheduler.(set_check_invariants (t ()) bool)
;;

let set_detect_invalid_access_from_thread bool =
  update_check_access (the_one_and_only ~should_lock:false) bool
;;

let set_record_backtraces bool =
  Kernel_scheduler.(set_record_backtraces (t ()) bool)
;;

module Expert = struct
  let set_on_start_of_cycle f = Kernel_scheduler.(set_on_start_of_cycle (t ()) f)
  let set_on_end_of_cycle   f = Kernel_scheduler.(set_on_end_of_cycle   (t ()) f)
end

let set_max_inter_cycle_timeout span =
  (the_one_and_only ~should_lock:false).max_inter_cycle_timeout <-
    Max_inter_cycle_timeout.create_exn (Time_ns.Span.of_span span)
;;

let start_busy_poller_thread_if_not_running t =
  if not t.busy_poll_thread_is_running
  then (
    t.busy_poll_thread_is_running <- true;
    let kernel_scheduler = t.kernel_scheduler in
    let _thread : Thread.t =
      Thread.create
        (fun () ->
           let rec loop () =
             lock t;
             if Busy_pollers.is_empty t.busy_pollers
             then (
               t.busy_poll_thread_is_running <- false;
               unlock t;
               (* We don't loop here, thus exiting the thread. *))
             else (
               Busy_pollers.poll t.busy_pollers;
               if Kernel_scheduler.num_pending_jobs kernel_scheduler > 0
               then (Kernel_scheduler.run_cycle kernel_scheduler);
               unlock t;
               (* The purpose of this [yield] is to release the OCaml lock while not
                  holding the async lock, so that the busy-poll loop spends a significant
                  fraction of its time not holding both locks, which thus allows other
                  OCaml threads that want to hold both locks the chance to run. *)
               Thread.yield ();
               loop ());
           in
           loop ())
        ()
    in
    ());
;;

let add_busy_poller poll =
  let t = the_one_and_only ~should_lock:true in
  let result = Busy_pollers.add t.busy_pollers poll in
  start_busy_poller_thread_if_not_running t;
  result
;;

type 'b folder = { folder : 'a. 'b -> t -> (t, 'a) Field.t -> 'b }

let t () = the_one_and_only ~should_lock:true

let fold_fields (type a) ~init folder : a =
  let t = t () in
  let f ac field = folder.folder ac t field in
  Fields.fold ~init
    ~mutex:f
    ~is_running:f
    ~have_called_go:f
    ~fds_whose_watching_has_changed:f
    ~file_descr_watcher:f
    ~time_spent_waiting_for_io:f
    ~fd_by_descr:f
    ~timerfd:f
    ~timerfd_set_at:f
    ~scheduler_thread_id:f
    ~interruptor:f
    ~signal_manager:f
    ~thread_pool:f
    ~handle_thread_pool_stuck:f
    ~busy_poll_thread_is_running:f
    ~busy_pollers:f
    ~next_tsc_calibration:f
    ~kernel_scheduler:f
    ~have_lock_do_cycle:f
    ~max_inter_cycle_timeout:f
    ~min_inter_cycle_timeout:f
    ~may_sleep_for_thread_fairness:f
;;

let handle_thread_pool_stuck f =
  let t = t () in
  let kernel_scheduler = t.kernel_scheduler in
  let execution_context = Kernel_scheduler.current_execution_context kernel_scheduler in
  t.handle_thread_pool_stuck <-
    (fun ~stuck_for ->
       Kernel_scheduler.enqueue kernel_scheduler execution_context
         (fun () -> f ~stuck_for) ());
;;

let yield () =
  let t = t () in
  Kernel_scheduler.yield t.kernel_scheduler;
;;

let yield_until_no_jobs_remain () =
  let t = t () in
  Kernel_scheduler.yield_until_no_jobs_remain t.kernel_scheduler;
;;

let yield_every ~n =
  let yield_every = Staged.unstage (Kernel_scheduler.yield_every ~n) in
  stage (fun () ->
    let t = t () in
    yield_every t.kernel_scheduler)
;;

let num_jobs_run () =
  let t = t () in
  Kernel_scheduler.num_jobs_run t.kernel_scheduler;
;;

let num_pending_jobs () =
  let t = t () in
  Kernel_scheduler.num_pending_jobs t.kernel_scheduler;
;;

let%test_unit _ = invariant (t ())
