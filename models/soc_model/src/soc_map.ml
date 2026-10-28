(* Memory map and parameters of the Linux SoC (issue #21): the single
   source for the SoC model, the device tree, the flash layout and (later)
   the HardCaml SoC. *)

let boot_rom_base = 0x0000_0000
let boot_rom_bytes = 0x1_0000 (* 64 KiB of block RAM *)
let clint_base = 0x0200_0000
let clint_bytes = 0x1_0000
let plic_base = 0x0c00_0000
let plic_bytes = 0x40_0000
let uart_base = 0x1000_0000
let uart_bytes = 0x100
let flash_base = 0x2000_0000
let flash_bytes = 0x80_0000 (* W25Q64JV, 8 MiB *)
let ram_base = 0x8000_0000
let ram_bytes = 0x80_0000 (* EM638325-6H, 8 MiB *)

(* Interrupt sources on the PLIC. *)
let uart_irq = 1
let plic_sources = 1

(* PLIC contexts of hart 0: machine and supervisor external interrupt. *)
let plic_context_m = 0
let plic_context_s = 1

(* CLINT timebase: mtime counts at 1 MHz (the hardware divides the system
   clock). *)
let timebase_hz = 1_000_000
let system_clock_hz = 50_000_000

(* Flash layout: the bitstream from 0, then the boot images. *)
let flash_dtb_offset = 0x20_0000
let flash_dtb_bytes = 0x1_0000
let flash_kernel_offset = 0x21_0000
let flash_kernel_bytes = flash_bytes - flash_kernel_offset

(* Where the boot ROM copies the kernel and starts it (S-mode). The
   kernel's first 4 MiB megapage holds the image. *)
let kernel_load = ram_base

let isa = "rv32ima" (* no C extension *)
let isa_extensions = [ "i"; "m"; "a"; "zicsr"; "zifencei"; "zicntr"; "sstc" ]
