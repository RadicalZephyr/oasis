
(** Test plugin META
    @author Sylvain Le Gall
  *)

open OUnit
open TestCommon
open Fl_metascanner
open OASISTypes
open OASISLibrary

let tests ctxt =
  let test_of_vector (nm, oasis_str, pkg_tests) =
    nm >::
    (bracket 
       (fun () ->
          Filename.temp_file "oasis-meta-" ".meta")
       (fun fn ->
          (* Parse string to get OASIS package *)
          let pkg = 
            OASIS.from_string 
              oasis_str
          in

          (* Generate META file *)
          let findlib_name_map =
            OASISLibrary.findlib_name_map pkg.libraries
          in
          let groups =
            OASISLibrary.group_libs pkg.libraries
          in
          let write_meta fndlb_nm =
            let grp = 
              try
                (* Find the package in all group *)
                List.find 
                  (fun grp ->
                     match grp with 
                       | Container (nm, _)
                       | Package (nm, _, _, _) -> nm = fndlb_nm)
                  groups
              with Not_found ->
                failwith 
                  (Printf.sprintf
                     "Cannot find group of name '%s'"
                     fndlb_nm)
            in
            let chn =
              open_out fn
            in
            let fmt =
              Format.formatter_of_out_channel chn
            in
              METAGen.pp_print_meta pkg findlib_name_map fmt grp;
              close_out chn
          in

          let dbug_meta () = 
            let chn =
              open_in fn
            in
              begin
                try
                  while true do
                    prerr_endline (input_line chn)
                  done
                with End_of_file ->
                  ()
              end;
              close_in chn
          in

          (* Check META file *)
          let rec find_pkg_defs pkg_expr = 
            function
              | hd :: tl ->
                  begin
                    try 
                      find_pkg_defs 
                        (List.assoc hd pkg_expr.pkg_children)
                        tl
                    with Not_found ->
                      failwith 
                        (Printf.sprintf 
                           "Could not find subpackage component '%s'"
                           hd)
                  end
              | [] -> 
                  pkg_expr.pkg_defs 
          in
            List.fold_left
              (fun former_meta (pkg_name, var, preds, res) ->
                 let pkg_root, pkg_paths =
                   match ExtString.String.nsplit pkg_name "." with
                     | hd :: tl -> hd, tl
                     | _ -> assert(false)
                 in
                 let pkg_expr = 
                   match former_meta with 
                     | Some (nm, pkg_expr) when nm = pkg_root -> 
                         pkg_expr
                     | _ ->
                         begin
                           let chn =
                             write_meta pkg_root;
                             if ctxt.dbug then
                               dbug_meta ();
                             open_in fn
                           in
                           let res =
                             parse chn
                           in
                             close_in chn;
                             res
                         end
                 in
                 let pkg_defs =
                   find_pkg_defs pkg_expr pkg_paths
                 in
                   begin
                     let msg = 
                       Printf.sprintf 
                         "%s %s(%s)"
                         pkg_name
                         var
                         (String.concat "," preds)
                     in
                       try 
                         assert_equal
                           ~msg
                           ~printer:(fun s -> s)
                           res
                           (lookup var preds pkg_defs)
                       with Not_found ->
                         failwith 
                           (Printf.sprintf 
                              "Cannot find META variable '%s'"
                              msg)
                   end;
                   Some (pkg_root, pkg_expr))
              None
              pkg_tests)
       (fun fn ->
          Sys.remove fn))
  in
    
    "META" >:::
    (List.map test_of_vector
       [
         "2-subpackages",
         "\
OASISFormat:  1.0
Name:         ocaml-data-notation
Version:      0.0.1
Synopsis:     store data using OCaml notation
License:      LGPL-LINK-EXN
Authors:      me

Library odn
  Path:    src
  Modules: ODN
  
Library pa_odn
  Path:              src
  Modules:           Pa_odn
  Parent:            odn
  XMETADescription:  Syntax extension for odn
  FindlibContainers: with
  FindlibName:       syntax

Library pa_noodn
  Path:              src
  Modules:           Pa_noodn
  Parent:            odn
  XMETADescription:  Syntax extension that removes 'with odn'
  FindlibContainers: without
  FindlibName:       syntax",
         [
           "odn", "archive", ["byte"], "odn.cma";
           "odn.with.syntax", "archive", ["byte"], "pa_odn.cma";
           
           "odn.without.syntax", "description", [], 
           "Syntax extension that removes 'with odn'";
         ];

         "virtual-root",
         "\
OASISFormat:  1.0
Name:         ocaml-data-notation
Version:      0.0.1
Synopsis:     store data using OCaml notation
License:      LGPL-LINK-EXN
Authors:      me

Library odn
  Path:    src
  Modules: ODN
  FindlibContainers:  myext.toto",
         [
           "myext.toto.odn", "archive", ["byte"], "odn.cma";
         ];

         "syntax",
         "\
OASISFormat:  1.0
Name:         ocaml-data-notation
Version:      0.0.1
Synopsis:     store data using OCaml notation
License:      LGPL-LINK-EXN
Authors:      me

Library odn
  Path:    src
  Modules: ODN

Library pa_odn
  Path:             src
  Modules:          Pa_odn
  Parent:           odn
  XMETADescription: Syntax extension for odn
  XMETAType:        syntax
  XMETARequires:    type-conv.syntax, camlp4
  FindlibName:      syntax",
         [
           "odn.syntax", "archive", ["syntax"; "preprocessor"], "pa_odn.cma";
           "odn.syntax", "archive", ["syntax"; "toploop"], "pa_odn.cma";
           "odn.syntax", "requires", [], "type-conv.syntax camlp4";
         ];
       ])