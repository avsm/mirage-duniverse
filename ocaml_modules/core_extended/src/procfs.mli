open! Core

(**
   Process and system stats
*)

type bigint = Big_int.big_int [@@deriving sexp] ;;

val input_all_with_reused_buffer : unit -> (string -> string) Staged.t

module Process : sig
  module Inode : sig
    type t [@@deriving sexp, bin_io] ;;
    val of_string : string -> t
    val to_string : t -> string
  end ;;
  module Limits : sig
    module Rlimit : sig
      type value = [ `unlimited | `limited of bigint ] [@@deriving sexp] ;;
      type t = { soft : value; hard: value } [@@deriving fields, sexp] ;;
    end ;;
    type t =
      {
        cpu_time          : Rlimit.t;
        file_size         : Rlimit.t;
        data_size         : Rlimit.t;
        stack_size        : Rlimit.t;
        core_file_size    : Rlimit.t;
        resident_set      : Rlimit.t;
        processes         : Rlimit.t;
        open_files        : Rlimit.t;
        locked_memory     : Rlimit.t;
        address_space     : Rlimit.t;
        file_locks        : Rlimit.t;
        pending_signals   : Rlimit.t;
        msgqueue_size     : Rlimit.t;
        nice_priority     : Rlimit.t;
        realtime_priority : Rlimit.t;
     }
    [@@deriving fields, sexp] ;;

    val of_string : string -> t
  end ;;
  module Stat : sig
    type t =
      {
        comm        : string; (** The filename of the executable *)
        state       : char;   (** One  character from the string "RSDZTW" *)
        ppid        : Pid.t option;  (** The PID of the parent. *)
        pgrp        : Pid.t option ;  (** The process group ID of the process. *)
        session     : int;    (** The session ID of the process. *)
        tty_nr      : int;    (** The tty the process uses. *)
        tpgid       : int;    (** The process group ID of the process which currently owns
                                  the tty... *)
        flags       : bigint; (** The kernel flags word of the process. *)
        minflt      : bigint; (** The number of minor faults the process has made which have
                                  not required loading a memory page from disk. *)
        cminflt     : bigint; (** The number of minor faults that the process’s waited-for
                                  children have made. *)
        majflt      : bigint; (** The number of major faults the process has made which have
                                  required loading a page from disk. *)
        cmajflt     : bigint; (** The number of major faults that the process’s waited-for
                                  children have made. *)
        utime       : bigint; (** The number of jiffies that this process has been scheduled
                                  in user mode. *)
        stime       : bigint; (** The number of jiffies that this process has been scheduled
                                  in kernel mode. *)
        cutime      : bigint; (** The number of jiffies that this process’s waited-for
                                  children have been scheduled in user mode. *)
        cstime      : bigint; (** The number of jiffies that this process’s waited-for
                                  children have been scheduled in kernel mode. *)
        priority    : bigint; (** The standard nice value, plus fifteen.  The value is never
                                  negative in the kernel. *)
        nice        : bigint; (** The nice value ranges from 19 to -19*)
        unused      : bigint; (** placeholder for removed field *)
        itrealvalue : bigint; (** The time in jiffies before the next SIGALRM is sent to the
                                  process due to an interval timer. *)
        starttime   : bigint; (** The time in jiffies the process started after system boot.*)
        vsize       : bigint; (** Virtual memory size in bytes. *)
        rss         : bigint; (** Resident Set Size: number of pages the process has in real
                                  memory. *)
        rlim        : bigint; (** Current limit in bytes on the rss of the process. *)
        startcode   : bigint; (** The address above which program text can run. *)
        endcode     : bigint; (** The address below which program text can run. *)
        startstack  : bigint; (** The address of the start of the stack. *)
        kstkesp     : bigint; (** The current value of esp (stack pointer) *)
        kstkeip     : bigint; (** The current value of eip (instruction pointer) *)
        signal      : bigint; (** The bitmap of pending signals. *)
        blocked     : bigint; (** The bitmap of blocked signals. *)
        sigignore   : bigint; (** The bitmap of ignored signals. *)
        sigcatch    : bigint; (** The bitmap of caught signals. *)
        wchan       : bigint; (** This is  the "channel" in which the process is waiting.
                                  Address of a system call. *)
        nswap       : bigint; (** (no longer maintained) *)
        cnswap      : bigint; (** (no longer maintained) *)
        exit_signal : int;    (** Signal sent to parent when we die. *)
        processor   : int;    (** CPU number last executed on. *)
        rt_priority : bigint; (** Real-time scheduling priority. *)
        policy      : bigint; (** Scheduling policy *)
      }
    [@@deriving fields, sexp] ;;

    (* For a stat string such as "14574 (cat) R 10615 14574 ...", extract_command returns
       (`command "cat", `rest "R 10615 14574 ..."). Note that the pid at the beginning is
       dropped. *)
    val extract_command : string -> [`command of string] * [`rest of string]

    val of_string : string -> t
  end ;;

  module Statm : sig
    type t =
      {
        size     : bigint; (** total program size *)
        resident : bigint; (** resident set size *)
        share    : bigint; (** shared pages *)
        text     : bigint; (** text (code) *)
        lib      : bigint; (** library *)
        data     : bigint; (** data/stack *)
        dt       : bigint; (** dirty pages (unused) *)
      }
    [@@deriving fields, sexp] ;;

    val of_string : string -> t
  end ;;

  module Status : sig
    type t =
      {
        uid   : int; (** Real user ID *)
        euid  : int; (** Effective user ID *)
        suid  : int; (** Saved user ID *)
        fsuid : int; (** FS user ID *)
        gid   : int; (** Real group ID *)
        egid  : int; (** Effective group ID *)
        sgid  : int; (** Saved group ID *)
        fsgid : int; (** FS group ID *)
      }
    [@@deriving fields, sexp] ;;

    val of_string : string -> t
  end ;;

  module Fd : sig
    type fd_stat =
      | Path of string
      | Socket of Inode.t
      | Pipe of Inode.t
      | Inotify
    [@@deriving sexp, bin_io] ;;
    type t =
      {
        fd      : int;     (** File descriptor (0=stdin, 1=stdout, etc.) *)
        fd_stat : fd_stat; (** Kind of file *)
      }
    [@@deriving fields, sexp, bin_io] ;;
  end ;;

  type t =
    {
      pid         : Pid.t;            (** Process ID *)
      cmdline     : string;           (** Command-line (not reliable). *)
      cwd         : string option;    (** Symlink to working directory. *)
      environ     : string option;    (** Process environment. *)
      exe         : string option;    (** Symlink to executed command. *)
      root        : string option;    (** Per-process root (e.g. chroot) *)
      limits      : Limits.t option;  (** Per-process rlimit settings *)
      stat        : Stat.t;           (** Status information. *)
      statm       : Statm.t;          (** Memory status information. *)
      status      : Status.t;         (** Some more assorted status information. *)
      task_stats  : Stat.t Pid.Map.t; (** Status information for each task (thread) *)
      top_command : string;           (** Show what top would show for COMMAND *)
      fds         : Fd.t list option; (** File descriptors *)
      oom_adj     : int;              (** OOM killer niceness [range: -17 to +15] *)
      oom_score   : int;              (** OOM "sacrifice" priority *)
    }
  [@@deriving fields, sexp] ;;
end ;;

module Meminfo : sig
  (** [t] corresponds to the values in /proc/meminfo.  All values in bytes. *)
  type t =
    {
      mem_total     : bigint;
      mem_free      : bigint;
      buffers       : bigint;
      cached        : bigint;
      swap_cached   : bigint;
      active        : bigint;
      inactive      : bigint;
      swap_total    : bigint;
      swap_free     : bigint;
      dirty         : bigint;
      writeback     : bigint;
      anon_pages    : bigint;
      mapped        : bigint;
      slab          : bigint;
      page_tables   : bigint;
      nfs_unstable  : bigint;
      bounce        : bigint;
      commit_limit  : bigint;
      committed_as  : bigint;
      vmalloc_total : bigint;
      vmalloc_used  : bigint;
      vmalloc_chunk : bigint;

      (* New field in CentOS 7 *)
      mem_available : bigint sexp_option;
    }
  [@@deriving fields, sexp] ;;

  val mem_available : t -> bigint
end ;;

module Kstat : sig
  type index_t = All | Number of int [@@deriving sexp]

  type cpu_t =
    {
      user    : bigint;
      nice    : bigint;
      sys     : bigint;
      idle    : bigint;
      iowait  : bigint option;
      irq     : bigint option;
      softirq : bigint option;
      steal   : bigint option;
      guest   : bigint option;
    } [@@deriving fields, sexp];;

  type t =
    index_t * cpu_t

  val load_exn : unit -> t list

end
module Loadavg : sig
  (** [t] corresponds to the values in /proc/loadavg. *)
  type t = {
    one : float;
    ten : float;
    fifteen : float;
  } [@@deriving fields]
end

(** [get_all_procs] returns a list of all processes on the system *)
val get_all_procs : unit -> Process.t list

(** [with_pid_exn pid] returns a single process that matches pid, or raises Not_found *)
val with_pid_exn : Pid.t -> Process.t

(** [with_pid pid] returns a single process that matches pid *)
val with_pid : Pid.t -> Process.t option

(** [with_uid uid] returns all processes owned by uid *)
val with_uid : int -> Process.t list

(** [pgrep f] returns all processes for which f is true *)
val pgrep : (Process.t -> bool) -> Process.t list

(** [pkill ~signal f] sends the signal to all processes for which f returns true. It
    returns the list of processes that were signaled, and the resulting errors if any. *)
val pkill
  : signal:Signal.t -> (Process.t -> bool) -> (Pid.t * (unit, Unix.Error.t) Result.t) list

(** [with_username_exn user] calls with_uid after looking up the user's uid *)
val with_username_exn : string -> Process.t list

(** [with_username user] calls with_uid after looking up the user's uid *)
val with_username : string -> Process.t list option

(** [jiffies_per_second_exn].  A jiffy "is one tick of the system timer interrupt.  It is
    not an absolute time interval unit, since its duration depends on the clock interrupt
    frequency of the particular hardware platform."

    Further reading: https://secure.wikimedia.org/wikipedia/en/wiki/Jiffy_(time)
 *)
val jiffies_per_second_exn : unit -> float
val jiffies_per_second : unit -> float option

(** [meminfo_exn] queries /proc/meminfo and fills out Meminfo.t.  All values in bytes. *)
val meminfo_exn : unit -> Meminfo.t
val meminfo : unit -> Meminfo.t option

(** [loadavg_exn] parses /proc/loadavg. *)
val loadavg_exn : unit -> Loadavg.t
val loadavg : unit -> Loadavg.t option

module Net : sig

  (*will put in some stuff from proc net *)

  module Dev : sig
    type t =
      {
      iface : string;
      rx_bytes  : int;
      rx_packets: int;
      rx_errs   : int;
      rx_drop   : int;
      rx_fifo   : int;
      rx_frame  : int;
      rx_compressed : bool;
      rx_multicast : bool;
      tx_bytes  : int;
      tx_packets: int;
      tx_errs   : int;
      tx_drop   : int;
      tx_fifo   : int;
      tx_colls  : int;
      tx_carrier: int;
      tx_compressed : bool;
      }
      [@@deriving fields];;

    val interfaces : unit -> string list

    val of_string : string -> t option
  end

  module Route : sig
  type t =
    {
      iface : string; (* maybe this shouldn't be a string? *)
      destination : Unix.Inet_addr.t;
      gateway     : Unix.Inet_addr.t;
      flags       : int;
      refcnt      : int;
      use         : int;
      metric      : int;
      mask        : Unix.Inet_addr.t;
      mtu         : int;
      window      : int;
      irtt        : int;
    }
  [@@deriving fields] ;;

  val default : unit -> Unix.Inet_addr.t

  end

  (* This should probably be somewhere else but I don't know where. *)
  module Tcp_state : sig
    type t =
        TCP_ESTABLISHED
        | TCP_SYN_SENT
        | TCP_SYN_RECV
        | TCP_FIN_WAIT1
        | TCP_FIN_WAIT2
        | TCP_TIME_WAIT
        | TCP_CLOSE
        | TCP_CLOSE_WAIT
        | TCP_LAST_ACK
        | TCP_LISTEN
        | TCP_CLOSING
        | TCP_MAX_STATES
    val to_int : t -> int
    val of_int : int -> t
  end

  (** /proc/net/tcp, or what netstat or lsof -i parses. *)
  module Tcp : sig
    type t =
      {
        sl : int;
        local_address : Core.Unix.Inet_addr.t;
        local_port : Extended_unix.Inet_port.t;
        remote_address : Core.Unix.Inet_addr.t;
        remote_port : Extended_unix.Inet_port.t option; (* can be 0 if there's no
        connection. *)
        state : Tcp_state.t;
        tx_queue : int;
        rx_queue : int;
        tr:int;
        tm_when : int;
        retrnsmt: int;
        uid : int;
        timeout : int;
        inode : Process.Inode.t;
        rest : string;
      } [@@deriving fields]

    (** These don't do any IO and should be async-ok *)
    val of_line : string -> t option
    val of_line_exn : string -> t

    (** This does IO and is not async-ok. *)
    val load_exn : unit -> t list

  end
end

module Mount : sig
  type t =
    {
      spec    : string; (* block device special name *)
      file    : string; (* fs path prefix *)
      vfstype : string; (* ext3, nfs, etc. *)
      mntops  : string list; (* mount options -o *)
      freq    : int; (* dump frequency *)
      passno  : int; (* pass number of parallel dump *)
    }
  [@@deriving fields] ;;
end

val mounts : unit -> Mount.t list

val mounts_of_fstab : unit -> Mount.t list

val supported_filesystems : unit -> string list

val uptime : unit -> Time.Span.t

val process_age : Process.t -> Time.Span.t option
val process_age' : jiffies_per_second : float -> Process.t -> Time.Span.t
