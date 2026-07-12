cmake_minimum_required(VERSION 3.8)
project(rm_serial)

find_package(rclcpp REQUIRED)
find_package(ament_cmake REQUIRED)
find_package(Eigen3 REQUIRED)
find_package(geometry_msgs REQUIRED)

add_library(serial_vendor STATIC
        third_party/serial/src/serial.cc
        third_party/serial/src/impl/unix.cc
        third_party/serial/src/impl/list_ports/list_ports_linux.cc
)
target_include_directories(serial_vendor PUBLIC
        third_party/serial/include
)
target_link_libraries(serial_vendor PUBLIC rt pthread)

include_directories(
        include
        third_party/serial/include
)

add_executable(rm_serial  src/uart_transporter.cpp
        src/talker.cpp
)

add_executable(talker src/talker.cpp)

ament_target_dependencies(rm_serial
        rclcpp
        geometry_msgs
)

ament_target_dependencies(talker
        rclcpp
        geometry_msgs
)

target_link_libraries(rm_serial
        Eigen3::Eigen
        serial_vendor
)

target_link_libraries(talker
        serial_vendor
)

install(TARGETS rm_serial
        talker
        DESTINATION lib/${PROJECT_NAME}
)
ament_package()
