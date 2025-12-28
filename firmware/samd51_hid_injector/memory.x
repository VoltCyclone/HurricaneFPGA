/* Memory layout for SAMD51J20A on Cynthion */
MEMORY
{
  /* SAMD51J20A has 1MB Flash, 256KB SRAM */
  /* Reserve first 8KB for Apollo bootloader */
  FLASH (rx)  : ORIGIN = 0x00002000, LENGTH = 0x000FE000  /* 1MB - 8KB */
  RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 0x00040000  /* 256KB */
}

/* Linker script sections */
_stack_start = ORIGIN(RAM) + LENGTH(RAM);
