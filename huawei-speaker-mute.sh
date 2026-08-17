#!/bin/bash
GPIOCHIP=gpiochip0
LINE=267
JACK_NUMID=27
I2C_BUS=2
CURRENT_PID=

reinit_amp() {
    sleep 0.3
    for ADDR in 0x58 0x5B; do
        i2cset -y -f $I2C_BUS $ADDR 0x01 0x69
        i2cset -y -f $I2C_BUS $ADDR 0x03 0x16
        i2cset -y -f $I2C_BUS $ADDR 0x04 0x80
        i2cset -y -f $I2C_BUS $ADDR 0x05 0x0c
        i2cset -y -f $I2C_BUS $ADDR 0x06 0x11
        i2cset -y -f $I2C_BUS $ADDR 0x07 0x93
        i2cset -y -f $I2C_BUS $ADDR 0x09 0x0b
        i2cset -y -f $I2C_BUS $ADDR 0x0b 0x4b
        i2cset -y -f $I2C_BUS $ADDR 0x0c 0x00
        i2cset -y -f $I2C_BUS $ADDR 0x0d 0x77
        i2cset -y -f $I2C_BUS $ADDR 0x0f 0x51
        i2cset -y -f $I2C_BUS $ADDR 0x10 0x58
        i2cset -y -f $I2C_BUS $ADDR 0x58 0x00
        i2cset -y -f $I2C_BUS $ADDR 0x59 0x80
        i2cset -y -f $I2C_BUS $ADDR 0x61 0x16
        i2cset -y -f $I2C_BUS $ADDR 0x62 0xb5
        i2cset -y -f $I2C_BUS $ADDR 0x63 0x5a
        i2cset -y -f $I2C_BUS $ADDR 0x64 0xd5
        i2cset -y -f $I2C_BUS $ADDR 0x65 0x57
        i2cset -y -f $I2C_BUS $ADDR 0x66 0x69
        i2cset -y -f $I2C_BUS $ADDR 0x67 0x28
        i2cset -y -f $I2C_BUS $ADDR 0x68 0x35
        i2cset -y -f $I2C_BUS $ADDR 0x69 0x98
        i2cset -y -f $I2C_BUS $ADDR 0x71 0x9c
        i2cset -y -f $I2C_BUS $ADDR 0x72 0x33
        i2cset -y -f $I2C_BUS $ADDR 0x73 0x40
        i2cset -y -f $I2C_BUS $ADDR 0x74 0x0c
    done
}

set_amp() {
    local val=$1
    if [ -n "$CURRENT_PID" ]; then
        kill "$CURRENT_PID" 2>/dev/null
        wait "$CURRENT_PID" 2>/dev/null
    fi
    # Новый синтаксис для libgpiod v2.x
    gpioset -c "$GPIOCHIP" "$LINE=$val" &
    CURRENT_PID=$!
    if [ "$val" = "1" ]; then
        reinit_amp
    fi
}

read_jack() {
    # Получаем статус подключения (on/off)
    amixer -c 0 cget "numid=$JACK_NUMID" 2>/dev/null \
        | sed -n 's/^[[:space:]]*: values=//p'
}

apply() {
    local jack
    jack=$(read_jack)
    if [ "$jack" = "on" ]; then
        set_amp 0
    else
        set_amp 1
    fi
}

cleanup() {
    [ -n "$CURRENT_PID" ] && kill "$CURRENT_PID" 2>/dev/null
    exit 0
}

trap cleanup TERM INT
apply
alsactl monitor hw:0 2>/dev/null | while read -r _; do
    apply
done
