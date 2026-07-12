#ifndef SPEED_PROTOCOL_H
#define SPEED_PROTOCOL_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct
{
    int16_t vx;
    int16_t vy;
    int16_t wz;
} SpeedCommand;

typedef struct
{
    uint8_t buffer[8];
    uint8_t index;
} SpeedParser;

void SpeedParser_Init(SpeedParser *parser);
bool SpeedParser_PushByte(
    SpeedParser *parser, uint8_t byte, SpeedCommand *out_command);

#ifdef __cplusplus
}
#endif

#endif
