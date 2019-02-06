module C = Configurator.V1

let detect_accelerate () =
  match Cpuid.supports [`SSSE3; `AES; `PCLMULQDQ] with
  | Ok r -> r
  | Error _ -> false

let parse_bool s =
  try bool_of_string s with
  | Invalid_argument _ ->
      C.die "Not a boolean: %s" s

let use_accelerate () =
  match Sys.getenv "NOCRYPTO_ACCELERATE" with
  | s -> parse_bool s
  | exception Not_found -> detect_accelerate ()

let flags () =
  let accelerate_flags =
    if use_accelerate () then
      ["-DACCELERATE -mssse3 -maes -mpclmul"]
    else
      []
  in
  let default_flags =
    ["-D_DEFAULT_SOURCE --std=c99 -Wall -Wextra -O3 -Wno-unused-function -Wno-implicit-fallthrough"]
  in
  default_flags @ accelerate_flags

let () =
  let output_path = ref "" in
  let args =
    let key = "--output" in
    let spec = Arg.Set_string output_path in
    let doc = "where the configuration should be written" in
    [(key, spec, doc)]
  in
  C.main ~args ~name:"nocrypto" (fun _ ->
      C.Flags.write_sexp !output_path (flags ()) )
