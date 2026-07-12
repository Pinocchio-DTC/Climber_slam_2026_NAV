#include "speed_protocol.h"

#include <stddef.h>

#define SPEED_FRAME_HEAD 0xFFU
#define SPEED_FRAME_TAIL 0xDDU
#define SPEED_FRAME_SIZE 8U

static int16_t read_i16_be(const uint8_t high, const uint8_t low)
{
    const uint16_t value = ((uint16_t)high << 8U) | (uint16_t)low;
    return (int16_t)value;
}

void SpeedParser_Init(SpeedParser *parser)
{
    if (parser != NULL)
    {
        parser->index = 0U;
    }
}

bool SpeedParser_PushByte(
    SpeedParser *parser, const uint8_t byte, SpeedCommand *out_command)
{
    if ((parser == NULL) || (out_command == NULL))
    {
        return false;
    }

    if (parser->index == 0U)
    {
        if (byte == SPEED_FRAME_HEAD)
        {
            parser->buffer[0] = byte;
            parser->index = 1U;
        }
        return false;
    }

    parser->buffer[parser->index++] = byte;
    if (parser->index < SPEED_FRAME_SIZE)
    {
        return false;
    }

    parser->index = 0U;
    if (parser->buffer[7] != SPEED_FRAME_TAIL)
    {
        if (byte == SPEED_FRAME_HEAD)
        {
            parser->buffer[0] = byte;
            parser->index = 1U;
        }
        return false;
    }

    out_command->vx = read_i16_be(parser->buffer[1], parser->buffer[2]);
    out_command->vy = read_i16_be(parser->buffer[3], parser->buffer[4]);
    out_command->wz = read_i16_be(parser->buffer[5], parser->buffer[6]);
    return true;
}
