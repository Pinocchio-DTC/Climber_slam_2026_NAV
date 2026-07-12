# 下位机速度帧解析示例

固定 8 字节帧格式：

```text
FF | vx_H | vx_L | vy_H | vy_L | wz_H | wz_L | DD
```

三个速度均为大端有符号 `int16_t`。`vx`、`vy` 单位为 mm/s，`wz` 单位为
0.001 rad/s。将 `speed_protocol.c/.h` 加入下位机工程，在串口接收中断中逐字节解析：

```c
static uint8_t uart_rx_byte;
static SpeedParser speed_parser;
volatile SpeedCommand chassis_speed_command;
volatile uint8_t chassis_speed_updated;

void SpeedUart_Start(void)
{
    SpeedParser_Init(&speed_parser);
    HAL_UART_Receive_IT(&huart1, &uart_rx_byte, 1);
}

void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance == USART1)
    {
        SpeedCommand command;
        if (SpeedParser_PushByte(&speed_parser, uart_rx_byte, &command))
        {
            chassis_speed_command = command;
            chassis_speed_updated = 1U;
        }
        HAL_UART_Receive_IT(&huart1, &uart_rx_byte, 1);
    }
}
```

主循环中可除以 `1000.0f` 恢复为 m/s 和 rad/s。实际使用时建议增加通信超时保护，
例如连续 300 ms 没收到有效帧就将三个目标速度清零。
