(* The Linux SoC as a model (issue #25): the golden model with M, A,
   Zifencei and S/U/Sv32, RAM at Soc_map.ram_base, and the devices of
   [Devices] at the addresses of [Soc_map]; the boot ROM and the flash
   window are read-only images.

   Time: mtime advances by one every [instructions_per_tick] retired
   instructions (default 50: a 1 MHz timebase at about one instruction per
   cycle at 50 MHz). The model takes an interrupt at every instruction
   boundary where the machine would take one. *)
open! Base
module M = Rv32_model.Machine

type t =
  { machine : M.t
  ; clint : Devices.Clint.t
  ; plic : Devices.Plic.t
  ; uart : Devices.Uart.t
  ; boot_rom : string
  ; flash : string
  ; instructions_per_tick : int
  ; mutable retired : int
  ; mutable interrupts : int
  }

let in_region addr ~base ~bytes = addr >= base && addr < base + bytes

let byte_of s off = if off < String.length s then Char.to_int s.[off] else 0xff

let read_image s off bytes =
  List.fold (List.range 0 bytes) ~init:0 ~f:(fun acc k -> acc lor (byte_of s (off + k) lsl (8 * k)))
;;

let create ?(instructions_per_tick = 50) ~boot_rom ~flash () =
  let clint = Devices.Clint.create () in
  let plic =
    Devices.Plic.create ~sources:Soc_map.plic_sources ~contexts:2
  in
  let uart = Devices.Uart.create () in
  let open Soc_map in
  let device addr =
    if in_region addr ~base:boot_rom_base ~bytes:boot_rom_bytes
    then Some `Rom
    else if in_region addr ~base:flash_base ~bytes:flash_bytes
    then Some `Flash
    else if in_region addr ~base:clint_base ~bytes:clint_bytes
    then Some `Clint
    else if in_region addr ~base:plic_base ~bytes:plic_bytes
    then Some `Plic
    else if in_region addr ~base:uart_base ~bytes:uart_bytes
    then Some `Uart
    else None
  in
  let io =
    { M.is_io = (fun addr -> Option.is_some (device addr))
    ; load =
        (fun ~addr ~bytes ->
          match device addr with
          | Some `Rom -> read_image boot_rom (addr - boot_rom_base) bytes
          | Some `Flash -> read_image flash (addr - flash_base) bytes
          | Some `Clint -> Devices.Clint.load clint (addr - clint_base)
          | Some `Plic -> Devices.Plic.load plic (addr - plic_base)
          | Some `Uart -> Devices.Uart.load uart (addr - uart_base)
          | None -> 0)
    ; store =
        (fun ~addr ~bytes:_ ~value ->
          match device addr with
          | Some `Clint -> Devices.Clint.store clint (addr - clint_base) value
          | Some `Plic -> Devices.Plic.store plic (addr - plic_base) value
          | Some `Uart -> Devices.Uart.store uart (addr - uart_base) value
          | Some `Rom | Some `Flash | None -> ())
    }
  in
  let rec t =
    lazy
      { machine =
          M.create
            ~io
            ~s:true
            ~m:true
            ~a:true
            ~zifencei:true
            ~mem_base:ram_base
            ~csr_input:(fun csr -> csr_input (Lazy.force t) csr)
            ~base:Rv32i
            ~mem_bytes:ram_bytes
            ()
      ; clint
      ; plic
      ; uart
      ; boot_rom
      ; flash
      ; instructions_per_tick
      ; retired = 0
      ; interrupts = 0
      }
  and csr_input t csr =
    let open Devices in
    match csr with
    | 0x344 ->
      (if t.clint.msip then 1 lsl 3 else 0)
      lor (if Clint.mtip t.clint then 1 lsl 7 else 0)
      lor (if Plic.irq t.plic ~context:Soc_map.plic_context_s then 1 lsl 9 else 0)
      lor if Plic.irq t.plic ~context:Soc_map.plic_context_m then 1 lsl 11 else 0
    | 0xc01 -> t.clint.time_lo
    | 0xc81 -> t.clint.time_hi
    | 0xb00 | 0xc00 -> t.retired land 0xffff_ffff
    | 0xb80 | 0xc80 -> (t.retired lsr 32) land 0xffff_ffff
    | 0xb02 | 0xc02 -> t.retired land 0xffff_ffff
    | 0xb82 | 0xc82 -> (t.retired lsr 32) land 0xffff_ffff
    | _ -> 0
  in
  let t = Lazy.force t in
  t.machine.pc <- Soc_map.boot_rom_base;
  t
;;

let receive t s = String.iter s ~f:(Devices.Uart.receive t.uart)
let output t = Buffer.contents t.uart.output

(* One instruction or interrupt entry. *)
let step t =
  Devices.Plic.set_level t.plic ~source:Soc_map.uart_irq (Devices.Uart.irq t.uart);
  let r =
    match M.pending_interrupt t.machine with
    | Some code ->
      t.interrupts <- t.interrupts + 1;
      (match M.interrupt t.machine ~code with
       | Ok r -> Ok r
       | Error msg -> failwith ("Soc.step: " ^ msg))
    | None -> M.step t.machine
  in
  t.retired <- t.retired + 1;
  if t.retired % t.instructions_per_tick = 0 then Devices.Clint.tick t.clint 1;
  r
;;
