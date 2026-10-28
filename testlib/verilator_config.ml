(* Verilator settings for every S2 stage.

   Ubuntu 24.04 and Debian trixie ship Verilator 5. [verbose = true] works
   around a hardcaml_verilator v0.17.0 bug: in quiet mode it appends the
   bash-only redirect "&>file" and runs the command with /bin/sh, which on
   Debian/Ubuntu (dash) backgrounds the build and races the final link.
   Build output therefore goes to stdout; S2 results go to stderr. *)
let config = { Hardcaml_verilator.Config.default with verilator_version = V5; verbose = true }
