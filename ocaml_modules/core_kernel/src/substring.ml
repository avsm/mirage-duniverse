open! Import

include Make_substring.F (struct
    type t = bytes

    let create = Bytes.create
    let length = Bytes.length
    let get    = Bytes.get
    module Blit = Make_substring.Blit
    let blit = Blit.bytes_bytes
    let blit_to_string = Blit.bytes_bytes
    let blit_to_bytes = Blit.bytes_bytes
    let blit_to_bigstring = Blit.bytes_bigstring
    let blit_from_string = Blit.string_bytes
    let blit_from_bigstring = Blit.bigstring_bytes
  end)
