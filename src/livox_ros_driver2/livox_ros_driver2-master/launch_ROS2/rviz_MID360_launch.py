import os
from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.conditions import IfCondition
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node
import launch

################### user configure parameters for ros2 start ###################
xfer_format   = 0    # 0-Pointcloud2(PointXYZRTL), 1-customized pointcloud format
multi_topic   = 0    # 0-All LiDARs share the same topic, 1-One LiDAR one topic
data_src      = 0    # 0-lidar, others-Invalid data src
publish_freq  = 10.0 # freqency of publish, 5.0, 10.0, 20.0, 50.0, etc.
output_type   = 0
frame_id      = 'livox_frame'
lvx_file_path = '/home/livox/livox_test.lvx'
cmdline_bd_code = 'livox0000000001'

cur_path = os.path.split(os.path.realpath(__file__))[0] + '/'
cur_config_path = cur_path + '../config'
rviz_config_path = os.path.join(cur_config_path, 'display_point_cloud_ROS2.rviz')
user_config_path = os.path.join(cur_config_path, 'MID360_config.json')
################### user configure parameters for ros2 end #####################

livox_ros2_params = [
    {"xfer_format": xfer_format},
    {"multi_topic": multi_topic},
    {"data_src": data_src},
    {"publish_freq": publish_freq},
    {"output_data_type": output_type},
    {"frame_id": frame_id},
    {"lvx_file_path": lvx_file_path},
    {"user_config_path": user_config_path},
    {"cmdline_input_bd_code": cmdline_bd_code}
]


def generate_launch_description():
    use_rviz = LaunchConfiguration('use_rviz')
    use_tf_tree = LaunchConfiguration('use_tf_tree')

    livox_driver = Node(
        package='livox_ros_driver2',
        executable='livox_ros_driver2_node',
        name='livox_lidar_publisher',
        output='screen',
        parameters=livox_ros2_params
        )

    # Standalone livox launch does not provide robot TF by default.
    # Publish a basic static transform so base_link and livox_frame are connected.


    livox_rviz = Node(
            condition=IfCondition(use_rviz),
            package='rviz2',
            executable='rviz2',
            output='screen',
            arguments=['--display-config', rviz_config_path]
        )

    # Optional TF graph GUI (requires: sudo apt install ros-$ROS_DISTRO-rqt-tf-tree)
    tf_tree_view = Node(
        condition=IfCondition(use_tf_tree),
        package='rqt_tf_tree',
        executable='rqt_tf_tree',
        output='screen'
    )

    baselink2livoxframe = Node(
        package="tf2_ros",
        executable="static_transform_publisher",
        arguments=[
            "--x",
            "0.0",
            "--y",
            "0.17",
            "--z",
            "-0.101",
            "--roll",
            "0.0",
            "--pitch",
            "0.7854",
            "--yaw",
            "1.5708",
            "--frame-id",
            "base_link",
            "--child-frame-id",
            "livox_frame"
        ]
    )

    chassis2baselink = Node(
        package="tf2_ros",
        executable="static_transform_publisher",
        arguments=[
            "--x",
            "0.0",
            "--y",
            "0.0",
            "--z",
            "0.406",
            "--roll",
            "0.0",
            "--pitch",
            "0.0",
            "--yaw",
            "0.0",
            "--frame-id",
            "chassis",
            "--child-frame-id",
            "base_link"
        ]
    )

    return LaunchDescription([
        DeclareLaunchArgument(
            'use_rviz',
            default_value='false',
            description='Launch Livox RViz point cloud viewer.',
        ),
        DeclareLaunchArgument(
            'use_tf_tree',
            default_value='false',
            description='Launch rqt_tf_tree.',
        ),
        livox_driver,
        livox_rviz,
        tf_tree_view,
        chassis2baselink,
        baselink2livoxframe
        # launch.actions.RegisterEventHandler(
        #     event_handler=launch.event_handlers.OnProcessExit(
        #         target_action=livox_rviz,
        #         on_exit=[
        #             launch.actions.EmitEvent(event=launch.events.Shutdown()),
        #         ]
        #     )
        # )
    ])
