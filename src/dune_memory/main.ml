open Dune_memory
open Stdune

let parse_metadata s =
  let rec convert = function
    | Sexplib.Sexp.Atom x ->
        Stdune.Sexp.Atom x
    | Sexplib.Sexp.List l ->
        Stdune.Sexp.List (List.map ~f:convert l)
  in
  match Sexplib.Sexp.parse s with
  | Sexplib.Sexp.Done (Sexplib.Sexp.List l, _) ->
      (* FIXME: check there's no leftover *)
      Result.Ok (List.map ~f:convert l)
  | Sexplib.Sexp.Cont _ ->
      Result.Error
        (User_error.E (User_error.make [Pp.textf "unfinished sexp"]))
  | _ ->
      Result.Error
        (User_error.E (User_error.make [Pp.textf "metadata must be a list"]))

let usage =
  Printf.sprintf "Usage: %s [OPTIONS] command [ARGUMENTS]" Sys.argv.(0)

let fill_option name ref s =
  match !ref with
  | None ->
      ref := Some s
  | Some _ ->
      User_error.raise [Pp.textf "duplicate option %s" name]

let unwrap_option ?default o = function
  | None -> (
    match default with
    | None ->
        User_error.raise [Pp.textf "missing required argument: %s" o]
    | Some v ->
        v )
  | Some v ->
      v

let main () =
  let root = ref None
  and cmd = ref None
  and current = ref (Array.length Sys.argv) in
  Arg.parse_argv Sys.argv
    [("--root", Arg.String (fill_option "--root" root), "root directory")]
    (fun a ->
      if !cmd = None then cmd := Some a
      else if !current = Array.length Sys.argv then current := !Arg.current - 1
      )
    usage ;
  let root = Option.map ~f:Path.of_string !root
  and cmd = unwrap_option "command" !cmd in
  let memory =
    Result.ok_exn
      (make ~log:(Log.create ~path:(Path.of_string "/tmp/log") ()) ?root ())
  in
  match cmd with
  | "promote" ->
      let usage = ""
      and metadata = ref None
      and files = ref (Array.make 0 "") in
      Arg.parse_argv ?current:(Some current) Sys.argv
        [ ( "--metadata"
          , Arg.String (fill_option "--metadata" metadata)
          , "metadata" ) ]
        (fun f -> files := Array.append !files (Array.make 1 f))
        usage ;
      let open Result.O in
      let produced =
        Array.to_list
          (Array.map
             ~f:(fun p ->
               let p = Path.of_string p in
               (p, Digest.file p) )
             !files)
      in
      Result.ok_exn
        ( parse_metadata (unwrap_option ~default:"()" "--metadata" !metadata)
        >>| fun metadata ->
        List.iter
          ~f:(fun p -> Printf.printf "%s\n" (promotion_to_string p))
          (promote memory produced
             (key (* FIXME: consumed files *) [] metadata
                (List.map ~f:fst produced))
             metadata None) )
  | "search" ->
      let open Result.O in
      Result.ok_exn
        ( parse_metadata Sys.argv.(3)
        >>= fun metadata ->
        search memory
          (key (* FIXME: consumed files *) [] metadata
             (* FIXME: produced files *) [])
        >>| function
        | _, paths ->
            List.iter
              ~f:(fun (sym, act) ->
                Printf.printf "%s: %s\n" (Path.to_string sym)
                  (Path.to_string act) )
              paths )
  | "trim" ->
      let freed, files = trim memory 1 in
      Printf.printf "freed %i bytes\n" freed ;
      List.iter ~f:(fun p -> Printf.printf "%s\n" (Path.to_string p)) files
  | _ ->
      User_error.raise [Pp.textf "unkown command: %s" cmd]

let () =
  try main () with
  | User_error.E msg ->
      Printf.fprintf stderr "%s: user error: %s\n" Sys.argv.(0)
        (Format.asprintf "%a@?" Pp.render_ignore_tags (User_message.pp msg)) ;
      exit 1
  | Sys_error msg ->
      Printf.fprintf stderr "%s: fatal error: %s\n" Sys.argv.(0) msg ;
      exit 2