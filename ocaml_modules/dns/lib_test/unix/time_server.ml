(*
 * Copyright (c) 2005-2012 Anil Madhavapeddy <anil@recoil.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Lwt

let time_rsrc_record () =
  Dns.Packet.(
    let name = Dns.Name.of_string_list ["time"; "com"] in
    let cls = RR_IN in
    let flush = false in
    let ttl = 100l in
    let time = string_of_float (Unix.gettimeofday ()) in
    let rdata = Dns.Packet.TXT [ "the"; "time"; "is"; time ] in
    { name; cls; flush; ttl; rdata }
  )

let dnsfn ~src:_ ~dst:_ query =
  let open Dns.Packet in
      match query.questions with
        | _q::_ -> (* Just take the first question *)
            return (Some
              Dns.Query.({
                rcode=NoError; aa=true;
                answer=[ time_rsrc_record () ]; authority=[]; additional=[];
              })
            )
        | _ -> return None (* No questions in packet *)

let _ =
  let address = "0.0.0.0" in
  let port = 5354 in
  let open Dns_server in
  let open Dns_server_unix in
  let processor = (processor_of_process dnsfn :> (module PROCESSOR)) in
  Lwt_main.run (serve_with_processor ~address ~port ~processor)
