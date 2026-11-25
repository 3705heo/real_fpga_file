# Trial settings for the COMM206 Spartan-7 board at 50 MHz.
# Confirm bank 16 is 3.3 V before programming. The trial uses LVCMOS33.
# Runner lights and RGB LED channels are assumed active-high (invert masks 0).
# An override may name a port bus (e.g. seg_com) or an individual bit (e.g. {seg_com[1]}).
set board [dict create \
    part {xc7s75fgga484-1} \
    clk_hz {50000000} \
    io_default {LVCMOS33} \
    io_overrides {
        clk_sys LVCMOS33
        sw_0 LVCMOS33 sw_1 LVCMOS33 sw_2 LVCMOS33 sw_3 LVCMOS33 sw_star LVCMOS33
        led LVCMOS33
        seg_com LVCMOS33 seg_data LVCMOS33
        piezo LVCMOS33
        rgb_r LVCMOS33 rgb_g LVCMOS33 rgb_b LVCMOS33
        lcd_data LVCMOS33 lcd_rs LVCMOS33 lcd_rw LVCMOS33 lcd_e LVCMOS33
    } \
    button_invert {0} \
    led_invert {0} \
    seg_com_invert {255} \
    seg_data_invert {0} \
    seg_reverse {0} \
    base_invert {0} \
    rgb_r_invert {0} \
    rgb_g_invert {0} \
    rgb_b_invert {0} \
    piezo_invert {0} \
    lcd_interface {HD44780_8BIT_WRITE} \
    lcd_data_invert {0} \
    lcd_ctrl_invert {0}]

# Invert masks are decimal integers. Use 0 for active-high signals.
# lcd_interface must be HD44780_8BIT_WRITE once this interface is confirmed.
