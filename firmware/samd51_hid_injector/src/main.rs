#![no_std]
#![no_main]

use panic_halt as _;

use cortex_m_rt::entry;

use atsamd_hal as hal;
use hal::clock::GenericClockController;
use hal::delay::Delay;
use hal::gpio::Pins;
use hal::pac::{CorePeripherals, Peripherals};
use hal::prelude::*;

use usb_device::prelude::*;
use usbd_serial::{SerialPort, USB_CLASS_CDC};
use usb_device::bus::UsbBusAllocator;
use core::fmt::Write;
use heapless;

mod uart;

use uart::UartInterface;
use samd51_hid_injector::protocol::{CommandProcessor, CommandType};
use samd51_hid_injector::descriptor_cache::DescriptorCache;

/// Debug output macro for USB-CDC serial
macro_rules! debug_write {
    ($serial:expr, $($arg:tt)*) => {{
        use core::fmt::Write;
        let mut buffer = heapless::String::<256>::new();
        let _ = write!(&mut buffer, $($arg)*);
        let _ = $serial.write(buffer.as_bytes());
    }};
}

#[entry]
fn main() -> ! {
    // Get peripheral instances
    let mut peripherals = Peripherals::take().unwrap();
    let core = CorePeripherals::take().unwrap();

    // Configure clocks
    let mut clocks = GenericClockController::with_internal_32kosc(
        peripherals.GCLK,
        &mut peripherals.MCLK,
        &mut peripherals.OSC32KCTRL,
        &mut peripherals.OSCCTRL,
        &mut peripherals.NVMCTRL,
    );

    let mut delay = Delay::new(core.SYST, &mut clocks);

    // Configure pins
    let pins = Pins::new(peripherals.PORT);

    // =======================================================================
    // USB CDC-ACM Setup (Host PC Communication)
    // =======================================================================
    
    static mut USB_BUS: Option<UsbBusAllocator<hal::usb::UsbBus>> = None;
    
    unsafe {
        let mut gclk0 = clocks.gclk0();
        let usb_bus = hal::usb::UsbBus::new(
            &clocks.usb(&mut gclk0).unwrap(),
            &mut peripherals.MCLK,
            pins.pa24,  // USB D-
            pins.pa25,  // USB D+
            peripherals.USB,
        );
        USB_BUS = Some(UsbBusAllocator::new(usb_bus));
    }
    
    let bus_allocator = unsafe { USB_BUS.as_ref().unwrap() };

    let mut serial = SerialPort::new(bus_allocator);

    let mut usb_dev = UsbDeviceBuilder::new(bus_allocator, UsbVidPid(0x1d50, 0x615c))
        .manufacturer("Great Scott Gadgets")
        .product("Cynthion HID Injector")
        .serial_number("HID-INJ-001")
        .device_class(USB_CLASS_CDC)
        .build();
    
    let mut usb_configured = false;
    let mut startup_sent = false;

    // =======================================================================
    // UART0 Setup (FPGA Communication)
    // =======================================================================
    // UART0 on pins R14 (TX) and T14 (RX) connected to FPGA
    
    let uart = UartInterface::new(
        peripherals.SERCOM0,
        &mut clocks,
        115200,  // Baud rate
        pins.pa04,  // TX (maps to R14 on Cynthion)
        pins.pa05,  // RX (maps to T14 on Cynthion)
    );

    // =======================================================================
    // Command Processor
    // =======================================================================
    
    let mut cmd_processor = CommandProcessor::new();
    
    // =======================================================================
    // HID Descriptor Cache
    // =======================================================================
    
    let mut descriptor_cache = DescriptorCache::new();
    
    // Status LED (Cynthion has an LED on the SAMD51)
    let mut led = pins.pa15.into_push_pull_output();
    led.set_high().unwrap();

    // =======================================================================
    // Main Loop
    // =======================================================================
    
    let mut rx_buffer = [0u8; 256];
    let mut tx_buffer = [0u8; 64];
    let mut loop_counter: u32 = 0;
    let mut last_usb_state = usb_dev.state();
    
    loop {
        loop_counter = loop_counter.wrapping_add(1);
        
        // Poll USB and detect state changes
        let poll_result = usb_dev.poll(&mut [&mut serial]);
        let current_usb_state = usb_dev.state();
        
        // Detect USB state transitions
        if current_usb_state != last_usb_state {
            last_usb_state = current_usb_state;
            match current_usb_state {
                UsbDeviceState::Default => {
                    debug_write!(serial, "[USB] State: Default (device reset)\r\n");
                    usb_configured = false;
                    startup_sent = false;
                }
                UsbDeviceState::Addressed => {
                    debug_write!(serial, "[USB] State: Addressed (address assigned)\r\n");
                }
                UsbDeviceState::Configured => {
                    debug_write!(serial, "[USB] State: Configured (device ready)\r\n");
                    usb_configured = true;
                }
                UsbDeviceState::Suspend => {
                    debug_write!(serial, "[USB] State: Suspend (low power)\r\n");
                }
            }
        }
        
        // Send startup banner once after configuration
        if usb_configured && !startup_sent {
            startup_sent = true;
            debug_write!(serial, "\r\n");
            debug_write!(serial, "========================================\r\n");
            debug_write!(serial, "Cynthion HID Injector v0.1.0\r\n");
            debug_write!(serial, "USB-CDC Debug Mode Enabled\r\n");
            debug_write!(serial, "========================================\r\n");
            debug_write!(serial, "[INIT] UART Baud: 115200\r\n");
            debug_write!(serial, "[INIT] Buffer sizes: RX=256, TX=64\r\n");
            debug_write!(serial, "[INIT] Ready for commands\r\n\r\n");
        }
        
        if poll_result {
            // Read commands from USB CDC-ACM
            match serial.read(&mut rx_buffer) {
                Ok(count) if count > 0 => {
                    debug_write!(serial, "[USB-RX] Received {} bytes: ", count);
                    
                    // Echo received data for debugging
                    for i in 0..count.min(32) {  // Limit echo to first 32 bytes
                        if rx_buffer[i] >= 0x20 && rx_buffer[i] <= 0x7E {
                            let _ = serial.write(&[rx_buffer[i]]);
                        } else {
                            debug_write!(serial, "<0x{:02X}>", rx_buffer[i]);
                        }
                    }
                    if count > 32 {
                        debug_write!(serial, "... ({} more)", count - 32);
                    }
                    let _ = serial.write(b"\r\n");
                    
                    // Parse command from host PC
                    debug_write!(serial, "[CMD] Parsing command...\r\n");
                    let cmd_result = cmd_processor.parse(&rx_buffer[..count], &mut descriptor_cache);
                    
                    match cmd_result {
                        CommandType::FpgaCommand(cmd) => {
                            debug_write!(serial, "[CMD] Type: FpgaCommand (code=0x{:02X}, len={})\r\n", 
                                       cmd.code, cmd.length);
                            
                            // Format command for FPGA and send via UART
                            let uart_msg = cmd.to_uart_frame();
                            debug_write!(serial, "[UART-TX] Sending to FPGA...\r\n");
                            uart.write(&uart_msg);
                            
                            // Echo acknowledgment back to USB
                            let ack = b"[OK] Command sent to FPGA\r\n";
                            let _ = serial.write(ack);
                        }
                        CommandType::Response => {
                            debug_write!(serial, "[CMD] Type: Response\r\n");
                            // Send response from processor
                            if let Some(response) = cmd_processor.get_response() {
                                debug_write!(serial, "[USB-TX] Sending response ({} bytes)\r\n", 
                                           response.len());
                                let _ = serial.write(response);
                            } else {
                                debug_write!(serial, "[WARN] No response data available\r\n");
                            }
                        }
                        CommandType::Restart => {
                            debug_write!(serial, "[CMD] Type: Restart\r\n");
                            // Send restart acknowledgment then restart
                            let msg = b"[SYS] Restarting device...\r\n";
                            let _ = serial.write(msg);
                            delay.delay_ms(100u8);
                            // TODO: Implement system reset via SCB
                            // cortex_m::peripheral::SCB::sys_reset();
                            debug_write!(serial, "[WARN] Restart not implemented\r\n");
                        }
                        CommandType::NoOp => {
                            debug_write!(serial, "[CMD] Type: NoOp (ignored)\r\n");
                        }
                    }
                }
                Ok(0) => {
                    // No data available - this is normal
                }
                Err(UsbError::WouldBlock) => {
                    // Would block - no data ready
                }
                Err(e) => {
                    debug_write!(serial, "[ERROR] USB read failed: {:?}\r\n", e);
                }
            }
            
            // Read status from FPGA UART
            if let Some(status) = uart.read_line() {
                debug_write!(serial, "[UART-RX] Received from FPGA: ");
                // Forward FPGA status to USB host
                let _ = serial.write(&status);
                let _ = serial.write(b"\r\n");
            }
        }
        
        // Periodic status (every ~10000 loops)
        if loop_counter % 10000 == 0 {
            if usb_configured {
                debug_write!(serial, "[HEARTBEAT] Loop={}, USB=OK\r\n", loop_counter);
            }
        }
        
        // Blink LED to show activity
        if loop_counter % 1000 == 0 {
            led.toggle().ok();
        }
        
        delay.delay_ms(1u8);
    }
}
