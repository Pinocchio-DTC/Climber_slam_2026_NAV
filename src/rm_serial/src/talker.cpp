#include "talker.hpp"

#include <array>
#include <exception>
#include <functional>

namespace
{
constexpr uint8_t FRAME_HEAD = 0xFF;
constexpr uint8_t FRAME_TAIL = 0xDD;
constexpr double SPEED_SCALE = 1000.0;
}  // namespace

ReceiveNode::ReceiveNode()
: Node("talker")
{
    this->declare_parameter("port_name", "/dev/ttySLAM");
    this->declare_parameter("baud_rate", 115200);
    port_name_ = this->get_parameter("port_name").as_string();
    baud_rate_ = this->get_parameter("baud_rate").as_int();

    serial_port_.setPort(port_name_);
    serial_port_.setBaudrate(baud_rate_);
    serial::Timeout timeout = serial::Timeout::simpleTimeout(100);
    serial_port_.setTimeout(timeout);

    cmd_vel_sub_ = this->create_subscription<geometry_msgs::msg::Twist>(
        "cmd_vel_nav", 10,
        std::bind(&ReceiveNode::cmd_vel_callback, this, std::placeholders::_1));
    timer_ = this->create_wall_timer(100ms, std::bind(&ReceiveNode::timer_callback, this));

    open_serial();
    RCLCPP_INFO(
        this->get_logger(),
        "Speed-only serial node started: topic=cmd_vel_nav port=%s baud=%d",
        port_name_.c_str(), baud_rate_);
}

ReceiveNode::~ReceiveNode()
{
    if (is_serial_open_)
    {
        serial_port_.close();
    }
}

bool ReceiveNode::open_serial()
{
    if (is_serial_open_)
    {
        return true;
    }

    try
    {
        serial_port_.open();
        is_serial_open_ = true;
        reported_serial_open_failure_ = false;
        RCLCPP_INFO(this->get_logger(), "Serial port opened: %s", port_name_.c_str());
        return true;
    }
    catch (const std::exception & e)
    {
        if (!reported_serial_open_failure_)
        {
            RCLCPP_WARN(
                this->get_logger(), "Failed to open serial port %s: %s",
                port_name_.c_str(), e.what());
            reported_serial_open_failure_ = true;
        }
        return false;
    }
}

void ReceiveNode::send_speed_packet()
{
    if (!is_serial_open_)
    {
        return;
    }

    // [帧头][vx 高低字节][vy 高低字节][wz 高低字节][帧尾]
    const std::array<uint8_t, 8> packet{
        FRAME_HEAD,
        static_cast<uint8_t>((cached_vx_ >> 8) & 0xFF),
        static_cast<uint8_t>(cached_vx_ & 0xFF),
        static_cast<uint8_t>((cached_vy_ >> 8) & 0xFF),
        static_cast<uint8_t>(cached_vy_ & 0xFF),
        static_cast<uint8_t>((cached_wz_ >> 8) & 0xFF),
        static_cast<uint8_t>(cached_wz_ & 0xFF),
        FRAME_TAIL};

    try
    {
        const size_t written = serial_port_.write(packet.data(), packet.size());
        if (written != packet.size())
        {
            RCLCPP_WARN(this->get_logger(), "Incomplete serial write: %zu/8 bytes", written);
        }
    }
    catch (const std::exception & e)
    {
        RCLCPP_WARN(this->get_logger(), "Serial write failed: %s", e.what());
        try
        {
            serial_port_.close();
        }
        catch (const std::exception &)
        {
        }
        is_serial_open_ = false;
    }
}

void ReceiveNode::cmd_vel_callback(const geometry_msgs::msg::Twist::SharedPtr msg)
{
    cached_vx_ = static_cast<int16_t>(msg->linear.x * SPEED_SCALE);
    cached_vy_ = static_cast<int16_t>(msg->linear.y * SPEED_SCALE);
    cached_wz_ = static_cast<int16_t>(msg->angular.z * SPEED_SCALE);
    send_speed_packet();
}

void ReceiveNode::timer_callback()
{
    if (open_serial())
    {
        send_speed_packet();
    }
}

int main(int argc, char * argv[])
{
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<ReceiveNode>());
    rclcpp::shutdown();
    return 0;
}
