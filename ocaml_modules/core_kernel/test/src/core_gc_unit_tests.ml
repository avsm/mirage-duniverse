open! Core_kernel
open! Gc

let%test_module "gc" [@tags "no-js"] =
  (module struct

    (* The idea underlying this test is that minor_words does not allocate any memory. Hence
       the subsequent call to quick_stat should report exactly the same number. Also:

       1) This test may fail if the float is so large that it cannot fit in a 64bit int.

       2) We run this in a loop because the each call to [quick_stat] allocates minor_data
       and this number should be picked up by [minor_words] *)
    let%test_unit _ =
      for _ = 1 to 1000 do
        let mw1 = minor_words () in
        let st = quick_stat () in
        let mw2 = Float.iround_towards_zero_exn st.Stat.minor_words in
        assert (mw1 = mw2);
      done

    (* The point of doing a [minor] in the tests below is that [st] is still live and will
       be promoted during the minor GC, thereby changing both the promoted words and the
       major words in each iteration of the loop *)
    let%test_unit _ =
      for _ = 1 to 1000 do
        let mw1 = major_words () in
        let st = quick_stat () in
        minor ();
        let mw2 = Float.iround_towards_zero_exn st.Stat.major_words in
        assert (mw1 = mw2);
      done

    let%test_unit _ =
      for _ = 1 to 1000 do
        let mw1 = promoted_words () in
        let st = quick_stat () in
        minor ();
        let mw2 = Float.iround_towards_zero_exn st.Stat.promoted_words in
        assert (mw1 = mw2);
      done

    let%test_unit _ =
      assert (major_words () + minor_words () = major_plus_minor_words ())

    let stat_eq func projection =
      (* In the stub the record is allocated after getting the stats, so we must ensure
         [func] is called first. *)
      let x = func () in
      let y = projection (quick_stat ()) in
      x = y
    ;;

    let%test_unit _ =
      for _ = 1 to 1000 do
        assert (stat_eq minor_collections Stat.minor_collections);
        minor ();
        assert (stat_eq minor_collections Stat.minor_collections);
      done

    let%test_unit _ =
      for _ = 1 to 250 do
        assert (stat_eq major_collections Stat.major_collections);
        major ();
        assert (stat_eq major_collections Stat.major_collections);
      done

    let%test_unit _ =
      for _ = 1 to 250 do
        assert (stat_eq compactions Stat.compactions);
        compact ();
        assert (stat_eq compactions Stat.compactions);
      done

    let%test_unit _ =
      let check () =
        assert (stat_eq heap_chunks Stat.heap_chunks);
        assert (stat_eq heap_words Stat.heap_words);
        assert (stat_eq top_heap_words Stat.top_heap_words);
      in
      check ();
      let r = ref [] in
      let n = heap_chunks () in
      while not (heap_chunks () > n) do
        check ();
        r := Bytes.create 128 :: !r
      done;
      check ()
  end)
