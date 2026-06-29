// ================================================================================ //
// ESP32-C6 transparent UART<->UART bridge for the NEORV32 (ZedBoard PL) UART0.        //
// -------------------------------------------------------------------------------- //
// Dumb wired serial bridge (no WiFi). Forwards bytes both ways between:               //
//   - UART0  -> the onboard CH343 USB-UART bridge -> PC COM port (PuTTY @19200-8N1)    //
//   - UART1  -> the FPGA (GPIO4 = RX, GPIO5 = TX) @19200-8N1                           //
// On the PC just open the ESP32's COM port in a terminal at 19200-8N1; the NEORV32     //
// bootloader/app text appears directly. No server, no WiFi.                            //
//                                                                                    //
// IMPORTANT: the IDF console is disabled (CONFIG_ESP_CONSOLE_NONE) so UART0 is free    //
// for the bridge. Flashing still works (ROM download mode is independent).             //
//                                                                                    //
// Onboard WS2812 RGB LED (GPIO8) smoothly shifts hue on every byte of traffic.         //
//                                                                                    //
// Wiring (3.3V only; power the ESP from its USB cable, NOT the ZedBoard VCC):          //
//   ZedBoard PMOD JA1 (FPGA TX) -> ESP32-C6 GPIO4 (UART1 RX)                          //
//   ZedBoard PMOD JA2 (FPGA RX) <- ESP32-C6 GPIO5 (UART1 TX)                          //
//   GND <-> GND (common ground required)                                             //
// ================================================================================ //

#include <string.h>
#include <math.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/uart.h"
#include "led_strip.h"

// ----------------------------- configuration ------------------------------------- //
#define PC_PORT        UART_NUM_0        // -> CH343 -> PC COM
#define PC_RX_PIN      17                // U0RXD (CH343 -> ESP), ESP32-C6 IOMUX default
#define PC_TX_PIN      16                // U0TXD (ESP -> CH343), ESP32-C6 IOMUX default
#define FPGA_PORT      UART_NUM_1        // -> ZedBoard PMOD JA
#define BAUD           19200             // NEORV32 bootloader = 19200-8N1
#define FPGA_RX_PIN    4                 // <- FPGA TX (PMOD JA1)
#define FPGA_TX_PIN    5                 // -> FPGA RX (PMOD JA2)
#define BUF_SIZE       2048

#define LED_GPIO       8
#define LED_BRIGHTNESS 40
// --------------------------------------------------------------------------------- //

static led_strip_handle_t s_led;
static volatile float s_target_hue = 0.0f;

static void hsv2rgb(float h, float s, float v, uint8_t *r, uint8_t *g, uint8_t *b) {
  h = h - 360.0f * (float)((int)(h / 360.0f));
  float c = v * s;
  float x = c * (1.0f - (float)fabs(fmod(h / 60.0f, 2.0f) - 1.0f));
  float m = v - c;
  float rf = 0, gf = 0, bf = 0;
  if      (h <  60) { rf = c; gf = x; }
  else if (h < 120) { rf = x; gf = c; }
  else if (h < 180) { gf = c; bf = x; }
  else if (h < 240) { gf = x; bf = c; }
  else if (h < 300) { rf = x; bf = c; }
  else              { rf = c; bf = x; }
  *r = (uint8_t)((rf + m) * 255.0f);
  *g = (uint8_t)((gf + m) * 255.0f);
  *b = (uint8_t)((bf + m) * 255.0f);
}

static void led_task(void *arg) {
  led_strip_config_t strip_cfg = {
    .strip_gpio_num = LED_GPIO,
    .max_leds = 1,
    .led_model = LED_MODEL_WS2812,
    .color_component_format = LED_STRIP_COLOR_COMPONENT_FMT_GRB,
  };
  led_strip_rmt_config_t rmt_cfg = {
    .resolution_hz = 10 * 1000 * 1000,
    .flags.with_dma = false,
  };
  ESP_ERROR_CHECK(led_strip_new_rmt_device(&strip_cfg, &rmt_cfg, &s_led));

  float cur = 0.0f;
  const float bv = (float)LED_BRIGHTNESS / 255.0f;
  while (1) {
    float tgt = s_target_hue;
    float d = tgt - cur;
    if (d > 2.0f) cur += 2.0f;
    else if (d < -2.0f) cur -= 2.0f;
    else cur = tgt;
    uint8_t r, g, b;
    hsv2rgb(cur, 1.0f, bv, &r, &g, &b);
    led_strip_set_pixel(s_led, 0, r, g, b);
    led_strip_refresh(s_led);
    vTaskDelay(pdMS_TO_TICKS(10));
  }
}

static inline void note_activity(void) { s_target_hue += 12.0f; }

static void port_init(uart_port_t port, int rx_pin, int tx_pin) {
  uart_config_t uc = {
    .baud_rate = BAUD,
    .data_bits = UART_DATA_8_BITS,
    .parity    = UART_PARITY_DISABLE,
    .stop_bits = UART_STOP_BITS_1,
    .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
    .source_clk = UART_SCLK_DEFAULT,
  };
  ESP_ERROR_CHECK(uart_driver_install(port, BUF_SIZE, BUF_SIZE, 0, NULL, 0));
  ESP_ERROR_CHECK(uart_param_config(port, &uc));
  if (rx_pin >= 0) {
    ESP_ERROR_CHECK(uart_set_pin(port, tx_pin, rx_pin, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));
  }
}

// PC -> FPGA
static void pc_to_fpga_task(void *arg) {
  uint8_t buf[512];
  while (1) {
    int n = uart_read_bytes(PC_PORT, buf, sizeof(buf), pdMS_TO_TICKS(20));
    if (n > 0) {
      uart_write_bytes(FPGA_PORT, (const char *)buf, n);
      note_activity();
    }
  }
}

void app_main(void) {
  port_init(PC_PORT, PC_RX_PIN, PC_TX_PIN);         // UART0 -> CH343 -> PC
  port_init(FPGA_PORT, FPGA_RX_PIN, FPGA_TX_PIN);   // UART1 to the FPGA

  xTaskCreate(led_task, "led", 3072, NULL, 4, NULL);
  xTaskCreate(pc_to_fpga_task, "pc2fpga", 4096, NULL, 6, NULL);

  // FPGA -> PC
  uint8_t buf[BUF_SIZE];
  while (1) {
    int n = uart_read_bytes(FPGA_PORT, buf, sizeof(buf), pdMS_TO_TICKS(20));
    if (n > 0) {
      uart_write_bytes(PC_PORT, (const char *)buf, n);
      note_activity();
    }
  }
}
