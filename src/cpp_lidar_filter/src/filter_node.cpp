#include <memory>
#include "rclcpp/rclcpp.hpp"
#include <chrono>
#include "sensor_msgs/msg/point_cloud2.hpp"
#include <pcl_conversions/pcl_conversions.h>
#include <pcl_ros/transforms.hpp>
#include <pcl/filters/crop_box.h>
#include <pcl/filters/voxel_grid.h>
#include <tf2/exceptions.h>
#include <tf2_ros/buffer.h>
#include <tf2_ros/transform_listener.h>
#include "visualization_msgs/msg/marker.hpp"

class LidarFilterNode : public rclcpp::Node
{
public:
  LidarFilterNode() : Node("lidar_filter_node")
  {
    this->declare_parameter("input_topic", "/livox/lidar");
    this->declare_parameter("output_topic", "/livox/lidar_filtered");
    this->declare_parameter("filter_frame", "base_link");
    this->declare_parameter("transform_tolerance", 0.2);
    // 裁剪参数 (CropBox)
    this->declare_parameter("min_x", -0.4);
    this->declare_parameter("max_x", 0.4);
    this->declare_parameter("min_y", -0.4);
    this->declare_parameter("max_y", 0.4);
    this->declare_parameter("min_z", -0.1);
    this->declare_parameter("max_z", 0.6);
    this->declare_parameter("negative", true); // true = 挖掉中间
    // 降采样参数
    this->declare_parameter("leaf_size", 0.05);

    std::string input_topic = this->get_parameter("input_topic").as_string();
    std::string output_topic = this->get_parameter("output_topic").as_string();
    filter_frame_ = this->get_parameter("filter_frame").as_string();
    transform_tolerance_ = this->get_parameter("transform_tolerance").as_double();

    RCLCPP_INFO(this->get_logger(), "Listening on: %s", input_topic.c_str());
    RCLCPP_INFO(this->get_logger(), "Publishing to: %s", output_topic.c_str());
    RCLCPP_INFO(this->get_logger(), "Filtering in frame: %s", filter_frame_.c_str());

    tf_buffer_ = std::make_unique<tf2_ros::Buffer>(this->get_clock());
    tf_listener_ = std::make_shared<tf2_ros::TransformListener>(*tf_buffer_);

    sub_ = this->create_subscription<sensor_msgs::msg::PointCloud2>(
      input_topic, rclcpp::SensorDataQoS(),
      std::bind(&LidarFilterNode::cloud_callback, this, std::placeholders::_1));

    pub_ = this->create_publisher<sensor_msgs::msg::PointCloud2>(
          output_topic, 10);
    marker_pub_ = this->create_publisher<visualization_msgs::msg::Marker>("crop_box_marker", 10);

    timer_ = this->create_wall_timer(
     std::chrono::milliseconds(1000), std::bind(&LidarFilterNode::publish_marker, this));
  }

private:
  void publish_marker() {
    double min_x = this->get_parameter("min_x").as_double();
    double max_x = this->get_parameter("max_x").as_double();
    double min_y = this->get_parameter("min_y").as_double();
    double max_y = this->get_parameter("max_y").as_double();
    double min_z = this->get_parameter("min_z").as_double();
    double max_z = this->get_parameter("max_z").as_double();

    visualization_msgs::msg::Marker marker;
    marker.header.frame_id = filter_frame_;
    marker.header.stamp = this->now();
    marker.ns = "vehicle_body";
    marker.id = 0;
    marker.type = visualization_msgs::msg::Marker::CUBE;
    marker.action = visualization_msgs::msg::Marker::ADD;

    // 计算中心点位置
    marker.pose.position.x = (max_x + min_x) / 2.0;
    marker.pose.position.y = (max_y + min_y) / 2.0;
    marker.pose.position.z = (max_z + min_z) / 2.0;
    marker.pose.orientation.w = 1.0;

    // 计算尺寸
    marker.scale.x = max_x - min_x;
    marker.scale.y = max_y - min_y;
    marker.scale.z = max_z - min_z;

    marker.color.r = 1.0;
    marker.color.g = 0.0;
    marker.color.b = 0.0;
    marker.color.a = 0.4; //半透明

    marker_pub_->publish(marker);
  }
  void cloud_callback(const sensor_msgs::msg::PointCloud2::SharedPtr msg)
  {
    if (msg->header.frame_id.empty()) {
      RCLCPP_WARN_THROTTLE(
        this->get_logger(), *this->get_clock(), 2000,
        "Input cloud has an empty frame_id, skip filtering.");
      return;
    }

    sensor_msgs::msg::PointCloud2 cloud_in_filter_frame;
    try {
      auto transform = tf_buffer_->lookupTransform(
        filter_frame_, msg->header.frame_id, msg->header.stamp,
        rclcpp::Duration::from_seconds(transform_tolerance_));
      pcl_ros::transformPointCloud(filter_frame_, transform, *msg, cloud_in_filter_frame);
    } catch (const tf2::TransformException & ex) {
      RCLCPP_WARN_THROTTLE(
        this->get_logger(), *this->get_clock(), 2000,
        "Failed to transform cloud from %s to %s: %s",
        msg->header.frame_id.c_str(), filter_frame_.c_str(), ex.what());
      return;
    }

    pcl::PCLPointCloud2::Ptr cloud_in(new pcl::PCLPointCloud2);
    pcl_conversions::toPCL(cloud_in_filter_frame, *cloud_in);

   // CropBox裁剪 (去除车身)
    pcl::CropBox<pcl::PCLPointCloud2> crop;
    crop.setInputCloud(cloud_in);

    // 设置裁剪盒子的范围
    Eigen::Vector4f min_pt, max_pt;
    min_pt << this->get_parameter("min_x").as_double(),
              this->get_parameter("min_y").as_double(),
              this->get_parameter("min_z").as_double(), 1.0;
    max_pt << this->get_parameter("max_x").as_double(),
              this->get_parameter("max_y").as_double(),
              this->get_parameter("max_z").as_double(), 1.0;

    crop.setMin(min_pt);
    crop.setMax(max_pt);
    crop.setNegative(this->get_parameter("negative").as_bool());

    pcl::PCLPointCloud2::Ptr cloud_cropped(new pcl::PCLPointCloud2);
    crop.filter(*cloud_cropped);

    // //降采样 (稀疏化)
    // pcl::VoxelGrid<pcl::PCLPointCloud2> sor;
    // sor.setInputCloud(cloud_cropped);
    // float leaf_size = this->get_parameter("leaf_size").as_double();
    // sor.setLeafSize(leaf_size, leaf_size, leaf_size);
    //
    // pcl::PCLPointCloud2::Ptr cloud_filtered(new pcl::PCLPointCloud2);
    // sor.filter(*cloud_filtered);

    sensor_msgs::msg::PointCloud2 output_in_filter_frame;
    pcl_conversions::fromPCL(*cloud_cropped, output_in_filter_frame);
    output_in_filter_frame.header = cloud_in_filter_frame.header;

    sensor_msgs::msg::PointCloud2 output;
    try {
      auto transform = tf_buffer_->lookupTransform(
        msg->header.frame_id, filter_frame_, msg->header.stamp,
        rclcpp::Duration::from_seconds(transform_tolerance_));
      pcl_ros::transformPointCloud(msg->header.frame_id, transform, output_in_filter_frame, output);
    } catch (const tf2::TransformException & ex) {
      RCLCPP_WARN_THROTTLE(
        this->get_logger(), *this->get_clock(), 2000,
        "Failed to transform filtered cloud from %s back to %s: %s",
        filter_frame_.c_str(), msg->header.frame_id.c_str(), ex.what());
      return;
    }
    output.header = msg->header;

    pub_->publish(output);
  }

  std::string filter_frame_;
  double transform_tolerance_;
  std::unique_ptr<tf2_ros::Buffer> tf_buffer_;
  std::shared_ptr<tf2_ros::TransformListener> tf_listener_;
  rclcpp::Subscription<sensor_msgs::msg::PointCloud2>::SharedPtr sub_;
  rclcpp::Publisher<sensor_msgs::msg::PointCloud2>::SharedPtr pub_;
  rclcpp::Publisher<visualization_msgs::msg::Marker>::SharedPtr marker_pub_;
  rclcpp::TimerBase::SharedPtr timer_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<LidarFilterNode>());
  rclcpp::shutdown();
  return 0;
}
