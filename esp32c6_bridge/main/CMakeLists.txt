idf_component_register(
  SRCS "bridge_main.c"
  INCLUDE_DIRS "."
  REQUIRES esp_driver_uart esp_driver_gpio led_strip
)
