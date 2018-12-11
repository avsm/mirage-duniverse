open Functoria
module Key = Mirage_key

let argv_unix = impl @@ object
    inherit base_configurable
    method ty = Functoria_app.argv
    method name = "argv_unix"
    method module_name = "Bootvar"
    method! packages =
      Key.pure [ package ~min:"0.1.0" ~max:"0.2.0" "mirage-bootvar-unix" ]
    method! connect _ _ _ = "Bootvar.argv ()"
  end

let argv_solo5 = impl @@ object
    inherit base_configurable
    method ty = Functoria_app.argv
    method name = "argv_solo5"
    method module_name = "Bootvar"
    method! packages =
      Key.pure [ package ~min:"0.3.0" ~max:"0.4.0" "mirage-bootvar-solo5" ]
    method! connect _ _ _ = "Bootvar.argv ()"
  end

let no_argv = impl @@ object
    inherit base_configurable
    method ty = Functoria_app.argv
    method name = "argv_empty"
    method module_name = "Mirage_runtime"
    method! connect _ _ _ = "Lwt.return [|\"\"|]"
  end

let argv_xen = impl @@ object
    inherit base_configurable
    method ty = Functoria_app.argv
    method name = "argv_xen"
    method module_name = "Bootvar"
    method! packages =
      Key.pure [ package ~min:"0.4.0" ~max:"0.5.0" "mirage-bootvar-xen" ]
    method! connect _ _ _ = Fmt.strf
      (* Some hypervisor configurations try to pass some extra arguments.
       * They means well, but we can't do much with them,
       * and they cause Functoria to abort. *)
      "let filter (key, _) = List.mem key (List.map snd Key_gen.runtime_keys) in@ \
       Bootvar.argv ~filter ()"
  end

let default_argv =
  match_impl Key.(value target) [
    `Xen, argv_xen;
    `Qubes, argv_xen;
    `Virtio, argv_solo5;
    `Hvt, argv_solo5;
    `Muen, argv_solo5;
    `Genode, argv_solo5
  ] ~default:argv_unix
