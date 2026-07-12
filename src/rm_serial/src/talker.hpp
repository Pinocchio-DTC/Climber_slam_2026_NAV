#ifndef TALKER_HPP
#define TALKER_HPP

#include <cstdint>
#include <memory>
#include <string>

#include "geometry_msgs/msg/twist.hpp"
#include "rclcpp/rclcpp.hpp"
#include "serial/serial.h"

using namespace std::chrono_literals;

class ReceiveNode : public rclcpp::Node
{
public:
    ReceiveNode();
    ~ReceiveNode() override;

private:
    rclcpp::Subscription<geometry_msgs::msg::Twist>::SharedPtr cmd_vel_sub_;
    rclcpp::TimerBase::SharedPtr timer_;
    serial::Serial serial_port_;
    std::string port_name_;
    int baud_rate_;
    bool is_serial_open_{false};
    bool reported_serial_open_failure_{false};
    int16_t cached_vx_{0};
    int16_t cached_vy_{0};
    int16_t cached_wz_{0};

    void cmd_vel_callback(const geometry_msgs::msg::Twist::SharedPtr msg);
    void timer_callback();
    bool open_serial();
    void send_speed_packet();
};

#endif
