(** Run this with [example.native --listen-prometheus=9090].
    View the metrics with:

    curl http://localhost:9090/metrics
   *)

open Lwt.Infix

module Metrics = struct
  open Prometheus

  let namespace = "MyProg"
  let subsystem = "main"

  let ticks_counted_total =
    let help = "Total number of ticks counted" in
    Counter.v ~help ~namespace ~subsystem "ticks_counted_total"
end

let rec counter () =
  Lwt_unix.sleep 1.0 >>= fun () ->
  print_endline "Tick!";
  Prometheus.Counter.inc_one Metrics.ticks_counted_total;
  counter ()

let main prometheus_config =
  let threads = counter () :: Prometheus_unix.serve prometheus_config in
  Lwt_main.run (Lwt.choose threads)

open Cmdliner

let () =
  print_endline "If run with the option --listen-prometheus=9090, this program serves metrics at\n\
                 http://localhost:9090/metrics";
  let spec = Term.(const main $ Prometheus_unix.opts) in
  let info = Term.info "example" in
  match Term.eval (spec, info) with
  | `Error _ -> exit 1
  | _ -> exit 0
