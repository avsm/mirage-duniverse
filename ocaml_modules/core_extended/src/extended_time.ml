open Core

module Extended_date = struct
  let format ?(ofday=Time.Ofday.start_of_day) s t =
    let zone = force Time.Zone.local in
    Time.format (Time.of_date_ofday t ofday ~zone) s ~zone
end

module Extended_span = struct
  let to_string_hum (t : Time.Span.t) =
    let sign_str =
      match Float.robust_sign (Time.Span.to_sec t) with
      | Neg -> "-"
      | Zero | Pos -> ""
    in
    let rest =
      match Float.classify (Time.Span.to_sec t) with
      | Float.Class.Subnormal | Float.Class.Zero -> "0:00:00.000"
      | Float.Class.Infinite -> "inf"
      | Float.Class.Nan -> "nan"
      | Float.Class.Normal ->
          let parts = Time.Span.to_parts t in
          let module P = Time.Span.Parts in
          sprintf "%d:%02d:%02d.%03d" parts.P.hr parts.P.min parts.P.sec parts.P.ms
    in
    sign_str ^ rest
end
