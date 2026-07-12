#include "uart_transporter.hpp"
#include <Eigen/Eigen>
#include "colortxt/color_txt.hpp"
#include "iostream"
#include "iomanip"
#include <vector>
#include <mutex>
#include <atomic>
#include <thread>
#include <chrono>
#include <rm_interfaces/msg/serial_receive_data.hpp>
#include <rclcpp/rclcpp.hpp>

// 添加必要的头文件
#include <memory>
#include <optional>  // 用于可选的返回值
// sendmsg 类
class sendmsg : public rclcpp::Node {
public:
    sendmsg()
        : Node("sendmsg") {
        // 创建发布器，发布到 SerialReceiveData 话题，队列大小为 10
        publisher_ = this->create_publisher<rm_interfaces::msg::SerialReceiveData>("SerialReceiveData", 10);
        // 创建定时器，每 50ms 调用一次回调函数
        timer_ = this->create_wall_timer(
            std::chrono::milliseconds(50),
            std::bind(&sendmsg::timer_callback, this));
    }

private:
    //接收串口消息
    bool receiveData(UartTransporter &uart) {
        uint8_t package[26];
        uint8_t header=0xff;
        if (!uart.open()) {
            std::cout << "Failed to open serial port" << std::endl;
            return false;
        }
        // 读取数据
        if (uart.read(package, sizeof(package)) == sizeof(package)) {
            if (header == package[0]) {
                std::memcpy(&hp,&package[18],sizeof(float));
                return true;
            }else {
                std::cout << "Failed to open serial port\n";
                std::cout << "invaild package header\n";
                return false;
            }
        }
        return false;
    }

    void timer_callback() {

        // 创建要发布的消息
        auto msg = rm_interfaces::msg::SerialReceiveData();

        if (receiveData(uart_)) {
            msg.source_mode = "seven";
            msg.hp = static_cast<uint16_t>(std::max(0.0f, hp));
            RCLCPP_INFO(this->get_logger(), "发布 hp: %u", msg.hp);
        }

        // 发布消息
        publisher_->publish(msg);
    }

    // 成员变量
    rclcpp::Publisher<rm_interfaces::msg::SerialReceiveData>::SharedPtr publisher_;
    rclcpp::TimerBase::SharedPtr timer_;
    UartTransporter uart_= UartTransporter("/dev/ttyACM0",115200);
    float hp = 400.0;
};

// 主函数
int main(int argc, char *argv[]) {
    // 初始化 ROS2
    rclcpp::init(argc, argv);


    // 创建 sendmsg 节点，传入 CODSerial 对象
    auto node = std::make_shared<sendmsg>();

    while (rclcpp::ok()) {
        // 处理ROS2事件，包括定时器回调
        rclcpp::spin_some(node);

        // 这里可以添加其他自定义任务
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }

    // 关闭 ROS2
    rclcpp::shutdown();

    return 0;
}
