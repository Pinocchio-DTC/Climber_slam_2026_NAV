import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
from launch.conditions import IfCondition
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration, PathJoinSubstitution
from launch_ros.actions import Node
from launch_ros.substitutions import FindPackageShare


def generate_launch_description():
    bringup_dir = get_package_share_directory('rm_bringup')

    config_file = LaunchConfiguration('config_file')
    publish_static_tf = LaunchConfiguration('publish_static_tf')
    use_rqt = LaunchConfiguration('use_rqt')
    use_rviz = LaunchConfiguration('use_rviz')
    rviz_config = LaunchConfiguration('rviz_config')

    static_tf = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            PathJoinSubstitution([
                FindPackageShare('rm_tf_bringup'),
                'launch',
                'static_tf.launch.py',
            ])
        ),
        condition=IfCondition(publish_static_tf),
        launch_arguments={'config_file': config_file}.items(),
    )

    return LaunchDescription([
        DeclareLaunchArgument(
            'config_file',
            default_value=PathJoinSubstitution([
                FindPackageShare('rm_tf_bringup'),
                'config',
                'static_transforms.yaml',
            ]),
            description='Static TF YAML file.',
        ),
        DeclareLaunchArgument(
            'publish_static_tf',
            default_value='true',
            description='Publish the configured static transforms.',
        ),
        DeclareLaunchArgument(
            'use_rqt',
            default_value='true',
            description='Open the live rqt TF tree viewer.',
        ),
        DeclareLaunchArgument(
            'use_rviz',
            default_value='false',
            description='Open RViz in addition to rqt_tf_tree.',
        ),
        DeclareLaunchArgument(
            'rviz_config',
            default_value=os.path.join(bringup_dir, 'rviz', 'cod_nav.rviz'),
            description='RViz configuration file.',
        ),
        static_tf,
        Node(
            condition=IfCondition(use_rqt),
            package='rqt_tf_tree',
            executable='rqt_tf_tree',
            output='screen',
        ),
        Node(
            condition=IfCondition(use_rviz),
            package='rviz2',
            executable='rviz2',
            arguments=['-d', rviz_config],
            output='screen',
        ),
    ])
