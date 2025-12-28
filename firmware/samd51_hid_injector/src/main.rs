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

mod uart;

use uart::UartInterface;
use samd51_hid_injector::protocol::{CommandProcessor, CommandType};
use samd51_hid_injector::descriptor_cache::DescriptorCache;

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
    
    loop {
        // Poll USB
        if usb_dev.poll(&mut [&mut serial]) {
            // Read commands from USB CDC-ACM
            match serial.read(&mut rx_buffer) {
                Ok(count) if count > 0 => {
                    // Parse command from host PC
                    let cmd_result = cmd_processor.parse(&rx_buffer[..count], &mut descriptor_cache);
                    
                    match cmd_result {
                        CommandType::FpgaCommand(cmd) => {
                            // Format command for FPGA and send via UART
                            let uart_msg = cmd.to_uart_frame();
                            uart.write(&uart_msg);
                            
                            // Echo acknowledgment back to USB
                            let ack = b"[OK]\n";
                            let _ = serial.write(ack);
                        }
                        CommandType::Response => {
                            // Send response from processor
                            if let Some(response) = cmd_processor.get_response() {
                                let _ = serial.write(response);
                            }
                        }
                        CommandType::Restart => {
                            // Send restart acknowledgment then restart
                            let msg = b"Restarting...\n";
                            let _ = serial.write(msg);
                            delay.delay_ms(100u8);
                            // TODO: Implement system reset via SCB
                            // cortex_m::peripheral::SCB::sys_reset();
                        }
                        CommandType::NoOp => {
                            // No action needed
                        }
                    }
                }
                _ => {}
            }
            
            // Read status from FPGA UART
            if let Some(status) = uart.read_line() {
                // Forward FPGA status to USB host
                let _ = serial.write(&status);
            }
        }
        
        // Blink LED to show activity
        delay.delay_ms(1u8);
    }
}
