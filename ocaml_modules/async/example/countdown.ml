open Core
open Async

let printf = Print.printf

let rec loop i =
  if i < 0 then
    shutdown 0
  else begin
    printf "%d\n" i;
    upon (after (sec 1.)) (fun _ -> loop (i - 1))
  end

let () = loop 10

let () = never_returns (Scheduler.go ())
